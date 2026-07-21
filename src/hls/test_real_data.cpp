// Integracioni test sa PRAVIM projektnim podacima (board2.txt + 12 sablona),
// isti CSV format/parsing kao tb.cpp::loadFile. Golden FEN je zvanicna
// referentna vrednost iz ESL/PEUSN dokumentacije (00 Pregled/(C) ESL dokumentacija
// - izvod.md): "rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R".
// Cilj: proveriti da ncc_kernel (Korak 1) na PRAVIM slikama daje isti FEN kao
// sto ga daje postojeci SystemC model (posredno, preko iste golden vrednosti).
#include "ncc_kernel.hpp"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <string>
#include <fstream>
#include <sstream>

using namespace std;

static void loadFile(const string& path, vector<int>& data, int& w, int& h) {
    ifstream f(path);
    if (!f.is_open()) { printf("[WARNING] Missing: %s\n", path.c_str()); return; }
    string line; h = 0; w = 0;
    while (getline(f, line)) {
        stringstream ss(line); string val; int row_w = 0;
        while (getline(ss, val, ',')) {
            data.push_back((int)stod(val));
            row_w++;
        }
        if (w == 0) w = row_w;
        h++;
    }
}

static void decode_fen(const string& fen, char board_state[8][8]) {
    for (int i = 0; i < 8; i++) for (int j = 0; j < 8; j++) board_state[i][j] = ' ';
    int m = 0, n = 0;
    for (char c : fen) {
        if (c == '/') { m++; n = 0; }
        else if (isdigit((unsigned char)c)) { n += (c - '0'); }
        else { board_state[m][n] = c; n++; }
    }
}

int main() {
    const string DATA_DIR = "data/data/";
    const char fen_map[12] = {'Q','N','K','B','P','R','q','n','k','b','p','r'};
    const string template_names[12] = {
        "Belakraljicatemplate.txt","Belikonjtemplate.txt","Belikraljtemplate.txt",
        "Belilovactemplate.txt","Belipesaktemplate.txt","Belitoptemplate.txt",
        "Crnakraljicatemplate.txt","Crnikonjtemplate.txt","Crnikraljtemplate.txt",
        "Crnilovactemplate.txt","Crnipesaktemplate.txt","Crnitoptemplate.txt"
    };
    const string GOLDEN_FEN = "rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R";

    char expected[8][8];
    decode_fen(GOLDEN_FEN, expected);

    printf("Ucitavam board2.txt...\n");
    vector<int> board_i; int iw, ih;
    loadFile(DATA_DIR + "board2.txt", board_i, iw, ih);
    printf("  board2.txt: %dx%d (ocekivano 720x720)\n", iw, ih);
    if (iw != 720 || ih != 720) { printf("DIMENZIJE NE ODGOVARAJU, prekidam.\n"); return 1; }

    vector<vector<int>> templ_i(12);
    int t_w[12], t_h[12];
    for (int i = 0; i < 12; i++) {
        loadFile(DATA_DIR + template_names[i], templ_i[i], t_w[i], t_h[i]);
        printf("  %s: %dx%d\n", template_names[i].c_str(), t_w[i], t_h[i]);
        if (t_w[i] > MAX_TMP_W || t_h[i] > MAX_TMP_H) {
            printf("SABLON PREVELIK ZA MAX_TMP_W/H (%d/%d), prekidam.\n", MAX_TMP_W, MAX_TMP_H);
            return 1;
        }
    }

    pixel_t templ_buf[12][MAX_TMP_PIX];
    for (int i = 0; i < 12; i++)
        for (size_t p = 0; p < templ_i[i].size(); p++)
            templ_buf[i][p] = (pixel_t)templ_i[i][p];

    const int seg_w = 90, seg_h = 90;
    int correct = 0, tested = 0, wrong_empty = 0, missed_piece = 0;

    printf("\n%-6s %-10s %-10s %-14s %-6s\n", "polje", "ocekivano", "predikcija", "NCC^2(best)", "match");
    for (int m = 0; m < 8; m++) {
        for (int n = 0; n < 8; n++) {
            char exp = expected[m][n];

            pixel_t seg[MAX_IMG_PIX];
            for (int y = 0; y < seg_h; y++)
                for (int x = 0; x < seg_w; x++)
                    seg[y*seg_w + x] = (pixel_t)board_i[(m*seg_h + y)*iw + (n*seg_w + x)];

            uint32_t best_score = 0;
            int best_idx = -1;
            for (int i = 0; i < 12; i++) {
                result_t result_map[MAX_IMG_PIX];
                ncc_kernel(seg, templ_buf[i], seg_w, seg_h, t_w[i], t_h[i], result_map);
                int res_w = seg_w - t_w[i] + 1, res_h = seg_h - t_h[i] + 1;
                for (int p = 0; p < res_w * res_h; p++)
                    if ((uint32_t)result_map[p] > best_score) { best_score = (uint32_t)result_map[p]; best_idx = i; }
            }

            const double THRESH2 = 0.75 * 0.75; // isti prag kao u projektu (gamma=0.75)
            double best_ratio = best_score / 2147483648.0;
            char predicted = (best_ratio > THRESH2) ? fen_map[best_idx] : ' ';

            bool match = (predicted == exp);
            if (exp != ' ' || predicted != ' ') {
                tested++;
                if (match) correct++;
                else if (exp == ' ' && predicted != ' ') wrong_empty++;
                else if (exp != ' ' && predicted == ' ') missed_piece++;
                printf("(%d,%d)  %-10c %-10c %-14.4f %s\n", m, n,
                       exp == ' ' ? '.' : exp, predicted == ' ' ? '.' : predicted,
                       best_ratio, match ? "OK" : "MISS");
            }
        }
    }

    printf("\n%d/%d polja tacno prepoznato (laznih pozitiva na praznom polju: %d, "
           "propustenih figura: %d)\n", correct, tested, wrong_empty, missed_piece);
    return (correct == tested) ? 0 : 1;
}

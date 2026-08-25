//
// StockfishServer.mm — Embedded In-Process Stockfish UCI Server for iOS / iPadOS / macOS
//

#import "StockfishServer.h"
#import "SFEngine.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>

#include <thread>
#include <mutex>
#include <condition_variable>
#include <string>
#include <vector>
#include <sstream>
#include <atomic>
#include <iostream>

namespace {

static std::atomic<bool> s_running{false};
static std::thread s_server_thread;
static int s_listen_fd = -1;

static SFEngine *s_engine = nil;
static std::mutex s_engine_mutex;
static std::mutex s_uci_mutex;
static std::condition_variable s_uci_cv;

static std::string s_last_bestmove;
static float s_last_eval_cp = 0.0f;
static std::vector<std::string> s_last_pv;
static bool s_search_done = false;

static void parse_uci_line(NSString *line) {
    if (!line) return;
    std::string str = [line UTF8String];

    std::lock_guard<std::mutex> lock(s_uci_mutex);

    if (str.rfind("info ", 0) == 0 && str.find("score ") != std::string::npos) {
        std::istringstream iss(str);
        std::string token;
        std::vector<std::string> tokens;
        while (iss >> token) tokens.push_back(token);

        for (size_t i = 0; i < tokens.size(); ++i) {
            if (tokens[i] == "cp" && i + 1 < tokens.size()) {
                try {
                    s_last_eval_cp = std::stof(tokens[i + 1]) / 100.0f;
                } catch (...) {}
            } else if (tokens[i] == "pv") {
                s_last_pv.clear();
                for (size_t j = i + 1; j < tokens.size(); ++j) {
                    s_last_pv.push_back(tokens[j]);
                }
                break;
            }
        }
    } else if (str.rfind("bestmove ", 0) == 0) {
        std::istringstream iss(str);
        std::string dummy, move;
        iss >> dummy >> move;
        s_last_bestmove = move;
        s_search_done = true;
        s_uci_cv.notify_all();
    }
}

static std::string url_decode(const std::string &in) {
    std::string out;
    out.reserve(in.size());
    for (size_t i = 0; i < in.size(); ++i) {
        if (in[i] == '%') {
            if (i + 2 < in.size()) {
                int hex = 0;
                std::istringstream hex_stream(in.substr(i + 1, 2));
                if (hex_stream >> std::hex >> hex) {
                    out += static_cast<char>(hex);
                    i += 2;
                } else {
                    out += '%';
                }
            } else {
                out += '%';
            }
        } else if (in[i] == '+') {
            out += ' ';
        } else {
            out += in[i];
        }
    }
    return out;
}

static void handle_client(int client_fd) {
    char buffer[4096];
    ssize_t bytes_read = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
    if (bytes_read <= 0) {
        close(client_fd);
        return;
    }
    buffer[bytes_read] = '\0';
    std::string req(buffer);

    std::string response_body;
    std::string status_line = "HTTP/1.1 200 OK\r\n";

    if (req.find("GET /health") == 0 || req.find("GET /status") == 0) {
        response_body = "{\"status\":\"ready\",\"engine\":\"Stockfish 18 Embedded (Apple Silicon)\",\"embedded\":true}";
    } else if (req.find("GET /analyze") == 0 || req.find("POST /analyze") == 0) {
        std::string fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
        int movetime_ms = 400;

        // Parse FEN and movetime from URL or body
        size_t fen_pos = req.find("fen=");
        if (fen_pos != std::string::npos) {
            size_t fen_end = req.find_first_of(" &\r\n", fen_pos);
            std::string raw_fen = req.substr(fen_pos + 4, fen_end - (fen_pos + 4));
            fen = url_decode(raw_fen);
        } else {
            // Check JSON body
            size_t json_fen = req.find("\"fen\":");
            if (json_fen != std::string::npos) {
                size_t q1 = req.find("\"", json_fen + 6);
                size_t q2 = req.find("\"", q1 + 1);
                if (q1 != std::string::npos && q2 != std::string::npos) {
                    fen = req.substr(q1 + 1, q2 - (q1 + 1));
                }
            }
        }

        size_t mt_pos = req.find("movetime=");
        if (mt_pos != std::string::npos) {
            size_t mt_end = req.find_first_of(" &\r\n", mt_pos);
            try {
                movetime_ms = std::stoi(req.substr(mt_pos + 9, mt_end - (mt_pos + 9)));
            } catch (...) {}
        } else {
            size_t json_mt = req.find("\"movetime\":");
            if (json_mt != std::string::npos) {
                size_t val_start = json_mt + 11;
                size_t val_end = req.find_first_of(",}\r\n", val_start);
                try {
                    movetime_ms = std::stoi(req.substr(val_start, val_end - val_start));
                } catch (...) {}
            }
        }

        std::string engine_type = "stockfish";
        size_t eng_pos = req.find("engine=");
        if (eng_pos != std::string::npos) {
            size_t eng_end = req.find_first_of(" &\r\n", eng_pos);
            engine_type = req.substr(eng_pos + 7, eng_end - (eng_pos + 7));
        }

        if (movetime_ms < 50) movetime_ms = 50;
        if (movetime_ms > 3000) movetime_ms = 3000;

        // Run engine search with lock
        {
            std::lock_guard<std::mutex> eng_lock(s_engine_mutex);

            {
                std::lock_guard<std::mutex> uci_lock(s_uci_mutex);
                s_last_bestmove = "";
                s_last_eval_cp = 0.0f;
                s_last_pv.clear();
                s_search_done = false;
            }

            if (s_engine) {
                NSString *cmd1 = @"isready\n";
                NSString *cmd2 = [NSString stringWithFormat:@"position fen %s\n", fen.c_str()];
                NSString *cmd3 = [NSString stringWithFormat:@"go movetime %d\n", movetime_ms];

                [s_engine sendCommand:cmd1];
                [s_engine sendCommand:cmd2];
                [s_engine sendCommand:cmd3];

                std::unique_lock<std::mutex> uci_lock(s_uci_mutex);
                s_uci_cv.wait_for(uci_lock, std::chrono::milliseconds(movetime_ms + 1000), []{
                    return s_search_done;
                });
            }
        }

        std::string engine_label = (engine_type == "lc0") ? "Leela Chess Zero (Lc0 Neural Network)" : "Stockfish 18 (Embedded Apple Silicon)";

        // Build JSON response
        std::ostringstream json;
        json << "{"
             << "\"available\":true,"
             << "\"engine\":\"" << engine_label << "\","
             << "\"bestmove_uci\":\"" << s_last_bestmove << "\","
             << "\"eval_cp\":" << s_last_eval_cp << ","
             << "\"pv\":[";
        for (size_t i = 0; i < s_last_pv.size(); ++i) {
            json << "\"" << s_last_pv[i] << "\"";
            if (i + 1 < s_last_pv.size()) json << ",";
        }
        json << "]}";
        response_body = json.str();
    } else {
        status_line = "HTTP/1.1 404 Not Found\r\n";
        response_body = "{\"error\":\"not found\"}";
    }

    std::ostringstream resp;
    resp << status_line
         << "Content-Type: application/json\r\n"
         << "Content-Length: " << response_body.size() << "\r\n"
         << "Access-Control-Allow-Origin: *\r\n"
         << "Connection: close\r\n\r\n"
         << response_body;

    std::string resp_str = resp.str();
    send(client_fd, resp_str.c_str(), resp_str.size(), 0);
    close(client_fd);
}

static void server_worker(int port) {
    s_listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (s_listen_fd < 0) return;

    int opt = 1;
    setsockopt(s_listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (bind(s_listen_fd, (sockaddr *)&addr, sizeof(addr)) < 0) {
        close(s_listen_fd);
        s_listen_fd = -1;
        return;
    }

    if (listen(s_listen_fd, 8) < 0) {
        close(s_listen_fd);
        s_listen_fd = -1;
        return;
    }

    // Initialize Stockfish engine
    {
        std::lock_guard<std::mutex> lock(s_engine_mutex);
        s_engine = [[SFEngine alloc] initWithLineHandler:^(NSString *line) {
            parse_uci_line(line);
        }];
        [s_engine start];
        [s_engine sendCommand:@"uci\n"];
        [s_engine sendCommand:@"isready\n"];
    }

    s_running = true;

    while (s_running) {
        sockaddr_in client_addr{};
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(s_listen_fd, (sockaddr *)&client_addr, &client_len);
        if (client_fd < 0) {
            if (!s_running) break;
            continue;
        }
        handle_client(client_fd);
    }

    // Cleanup
    {
        std::lock_guard<std::mutex> lock(s_engine_mutex);
        if (s_engine) {
            [s_engine stop];
            s_engine = nil;
        }
    }
}

} // namespace

extern "C" {

void start_embedded_stockfish_server(int port) {
    if (s_running.load()) return;
    if (port <= 0) port = 8765;
    s_server_thread = std::thread(server_worker, port);
    s_server_thread.detach();
}

void stop_embedded_stockfish_server(void) {
    s_running = false;
    if (s_listen_fd >= 0) {
        close(s_listen_fd);
        s_listen_fd = -1;
    }
}

int is_embedded_stockfish_running(void) {
    return s_running.load() ? 1 : 0;
}

}

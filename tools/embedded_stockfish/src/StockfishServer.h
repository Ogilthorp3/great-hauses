//
// StockfishServer.h — Embedded In-Process Stockfish UCI Server for iOS / iPadOS / macOS
//
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void start_embedded_stockfish_server(int port);
void stop_embedded_stockfish_server(void);
int is_embedded_stockfish_running(void);

#ifdef __cplusplus
}
#endif

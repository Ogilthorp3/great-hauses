extends RefCounted
class_name ChessMove

# Ported from "Stop Waiting For Godot" chess (https://github.com/thearst3rd/stopwaitingforgodot)
# Copyright (c) 2021 Terry Hearst, MIT License — see LICENSE-stopwaitingforgodot in this directory.
# Portions of this file are additions for the Great Houses engine (presentation metadata, UCI helpers).
#
# Everything needed to play out or undo a move, plus presentation-agnostic
# metadata so a rendering layer (2D/3D) can animate directly from move data.

## Core engine fields (verbatim port) ##

var from_square := -1
var to_square := -1
var promotion = null           # null, or piece char ("Q"/"q"/"N"/... matching mover color)
var captured_piece = null      # piece char on to_square (null for non-captures AND for en passant)
var en_passant := false
var lose_castling := [false, false, false, false]
var prev_ep_target = null
var prev_halfmove_clock = -1
var notation_san = null

## Presentation metadata (additions — set by ChessState.construct_move, not used by play/undo) ##

var piece := ""                # the moving piece char, e.g. "P" or "n"
var is_castling := false       # true when this is O-O or O-O-O
var castle_kingside := false   # valid when is_castling
var rook_from := -1            # rook start square when is_castling
var rook_to := -1              # rook end square when is_castling
var captured_square := -1      # square of the captured piece (differs from to_square for en passant); -1 if no capture


func duplicate():
	var new_move = get_script().new()
	new_move.from_square = from_square
	new_move.to_square = to_square
	new_move.promotion = promotion
	new_move.captured_piece = captured_piece
	new_move.en_passant = en_passant
	new_move.lose_castling = lose_castling.duplicate()
	new_move.prev_ep_target = prev_ep_target
	new_move.prev_halfmove_clock = prev_halfmove_clock
	new_move.notation_san = notation_san
	new_move.piece = piece
	new_move.is_castling = is_castling
	new_move.castle_kingside = castle_kingside
	new_move.rook_from = rook_from
	new_move.rook_to = rook_to
	new_move.captured_square = captured_square
	return new_move


func is_capture() -> bool:
	return captured_piece != null or en_passant


static func square_name(sq: int) -> String:
	if sq < 0 or sq >= 64:
		return "-"
	@warning_ignore("integer_division")
	return char("a".unicode_at(0) + (sq % 8)) + str(8 - (sq / 8))


# Long algebraic / UCI form, e.g. "e2e4", "e7e8q"
func to_uci() -> String:
	var promo := ""
	if promotion != null:
		promo = str(promotion).to_lower()
	return square_name(from_square) + square_name(to_square) + promo


func _to_string() -> String:
	return to_uci()

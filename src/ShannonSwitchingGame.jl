module ShannonSwitchingGame

include("game.jl") # Datenstrukturen + Spiellogik
include("gui.jl") # Gtk4-Fenster + Cairo-Zeichnung
include("ki.jl")

export random_graph, check_st_connection, new_game, valid_moves, make_move!
export FC, gemeinsame_Sehnen, Augment, kruskal, DFS, find_path, search_connecting_edge, MaximallyDistantTrees
export run_gui

end 

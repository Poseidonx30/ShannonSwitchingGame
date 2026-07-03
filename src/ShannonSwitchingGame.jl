module ShannonSwitchingGame

include("game.jl") # Datenstrukturen + Spiellogik
include("Wettbewerbsstrategie_Hilfsfunktionen.jl")
include("Wettbewerbsstrategie.jl")
include("gui.jl") # Gtk4-Fenster + Cairo-Zeichnung
#include("ki.jl")
export random_graph, check_st_connection, new_game, valid_moves, make_move!
export FC, gemeinsame_Sehnen, Augment, kruskal, DFS, find_path, search_connecting_edge, MaximallyDistantTrees, chase
export run_gui
export dijkstra, weighted_cut, weighted_short

end 

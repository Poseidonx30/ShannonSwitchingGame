module ShannonSwitchingGame

include("game.jl") # Datenstrukturen + Spiellogik
include("gui.jl") # Gtk4-Fenster + Cairo-Zeichnung
include("ki.jl")

export random_graph, new_game, valid_moves, make_move!
export run_gui

end 

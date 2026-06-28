const TEAM_NAME::String = "StockFisch 1.0"

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

mutable struct ExtendedGameState
    graph::EfficientGameGraph
    merged_graph::EfficientGameGraph
    A::Base.Set{Edge} 
    B::Base.Set{Edge} 
    e1::Edge
    has_winning_strategy::Symbol
    current_player::Symbol
    history::Vector{Tuple{Symbol, Edge}} 
    imaginary_moves::Base.Set{Edge}
    winner::Union{Symbol, Nothing}
end

mutable struct EfficientGameGraph
    edges::Base.Set{Edge}  
    components::ComponentTracker      #Short fügt hierin zusammen
    s::Vertex                 
    t::Vertex                 
end

struct ComponentTracker   #Für effizientes Tracken von Zusammenhangskomponenten (hat Gemini in dieser Art vorgeschlagen - ist wohl etwas effizienter als unsere alte Struktur)
    parent::Vector{Int}
    size::Vector{Int}
end

Base.copy(ct::ComponentTracker) = ComponentTracker(copy(ct.parent), copy(ct.size))

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)


function weighted_cut(state::GameState)::Edge 
    if length(state.history) == 1 #Initialisieren vom Extended State
        e1 = Edge(Inf, state.graph.s, state.graph.t)
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Vector{Int}(), Vector{Int}()), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.vertices], ones(Int, length(state.vertices))), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, :neutral, :cut, copy(state.history), Base.Set{Edge}(), nothing)
    end 
    if EXTENDED_STATE[].winner != :cut  #noch nicht gewonnen (im aktuellen merged graph, nicht allgemein)
        EXTENDED_STATE[].winner = (check_st_connection(merged_graph) == false) ? :cut : nothing
    end
    if EXTENDED_STATE[].winner == :cut  #schon gewonnen (im aktuellen merged graph sind s und t nicht mehr verbunden)
        return rand(valid_moves(state))
    end 

    if state.has_winning_strategy == :cut
        return chase(state)
    else 
        shorts_edge = state.history[end][2]
        merged_graph = EXTENDED_STATE[].merged_graph
        if !(get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.s) && get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.t) 
            || get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.s) && get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.t))
            merge_graph!(merged_graph.components, shorts_edge)  #neue Zusammenhangskomponenten setzen; s und t sollen nicht in einem Zshk. kommen
        end 
        delete!(merged_graph.edges, shorts_edge)
        if who_can_win(merged_graph, false) == :cut  #false, da für cut Gewichtung nicht interessant, falls optimale Strategie existiert (sofern Strafe für short hoch genug - hoffe ich mal)
            return chase(state)
        else
            return #MCTS
        end 
    end 
end



function weighted_short(state::GameState)::Edge
#= Hier gibt es verschiedene Möglichkeiten. Wir könnten nur MCTS verwenden. Ein Vorschlag von Gemini (der für mich ganz gut klingt), wäre MCTS zu verwenden, 
falls es keine optimale Strategie gibt (klar). Und im Fall einer optimalen Strategie,
MCTS anzuwenden auf die möglichen optimalen Antwort-Kanten, um nicht nur lokal das günstigste zu wählen, sondern auch in die Zukunft zu schauen. Die optimale Strategie ist aber auch nicht ganz so einfach übertragbar.
Ich habe es jetzt so angepasst, dass Krukal auch einen minimalen Spannbaum berechnen kann und die Sehnen ihrem Gewicht nach geordnet zum Augmentieren probiert werden (falls true übergeben wird für minimal).
Vlt. ist aber auch ein reiner guter MCTS Alg. besser. (siehe auch chase Alg in den Hilfsfunktionen) =#
end

function MCTS(state::GameState; Zeitlimit = 1.0)::Edge
     
end 



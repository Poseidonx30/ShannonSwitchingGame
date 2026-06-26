const TEAM_NAME::String = "StockFisch 1.0"

mutable struct ExtendedGameState
    graph::EfficientGameGraph
    short_Graph::EfficientGameGraph
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
    s::Int                 
    t::Int                 
end

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)


function weighted_short(state::GameState)::Edge
    if isempty(state.history)
    I_can_win = who_can_win() == :short ?...
end

function weighted_cut(state::GameState)::Edge 
    
end

function MCTS(state::GameState; Zeitlimit = 1.0)
     
end 



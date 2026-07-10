const TEAM_NAME::String = "StockFisch 1.2"

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)
const EXTENDED_STATE2 = Ref{Union{Nothing, ExtendedGameState}}(nothing)

function weighted_cut(state::GameState)::Edge
    start_time = time() 
    if length(state.history) == 1 
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(state.graph.vertices, Vector{Edge}(), state.graph.s, state.graph.t)
        sizehint!(short_graph.edges, length(state.graph.edges))
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Int[]), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :cut, false, Base.Set{Edge}(), nothing)
    end 
    shorts_edge = state.history[end][2]
    short_graph = EXTENDED_STATE[].short_graph
    push!(short_graph.edges, shorts_edge)  
    if EXTENDED_STATE[].winner != :cut  
        EXTENDED_STATE[].winner = (check_st_connection(EXTENDED_STATE[].merged_graph) == false) ? :cut : nothing
    end
    if EXTENDED_STATE[].winner == :cut  
        return rand(valid_moves(state))
    end 

    if EXTENDED_STATE[].winner == :short
        end_time = time()   
        return @time MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time))
    end 
    
    if EXTENDED_STATE[].has_winning_strategy == :cut
        cuts_edge = chase(EXTENDED_STATE[], state)
    else 
        merged_graph = EXTENDED_STATE[].merged_graph
        merge_components!(merged_graph.components, shorts_edge.u.id, shorts_edge.v.id)
        delete!(merged_graph.edges, shorts_edge)
        if (get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.t.id) 
            || get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.t.id))
    
            EXTENDED_STATE[].winner = :short
            end_time = time()   
            return @time MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time))
        end 
        who_can_win(EXTENDED_STATE[], false)
        if EXTENDED_STATE[].has_winning_strategy == :cut  
            EXTENDED_STATE[].first_optimal_move = true 
            cuts_edge = chase(EXTENDED_STATE[], state)
        else
            end_time = time()   
            cuts_edge = @time MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time))
        end 
    end 
    delete!(EXTENDED_STATE[].merged_graph.edges, cuts_edge)
    return cuts_edge
end

function weighted_short(state::GameState)::Edge
    start_time = time()
    len = length(state.history)
    if len == 0 
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(state.graph.vertices, Vector{Edge}(), state.graph.s, state.graph.t)
        sizehint!(short_graph.edges, length(state.graph.edges))
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Int[]), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :short, false, Base.Set{Edge}(), nothing)
    end 
    merged_graph = EXTENDED_STATE[].merged_graph
    if len != 0
        shorts_old_edge = state.history[end-1][2]
        delete!(merged_graph.edges, state.history[end][2])   
        delete!(merged_graph.edges, shorts_old_edge)
        merge_components!(merged_graph.components, shorts_old_edge.u.id, shorts_old_edge.v.id)
        short_graph = EXTENDED_STATE[].short_graph
        push!(short_graph.edges, shorts_old_edge) 
    end
    end_time = time()
    shorts_edge = @time MCTS(EXTENDED_STATE[], state, time_limit = 1.7 - (end_time - start_time)) 
    return shorts_edge
end
mutable struct MCTS_node
    parent::Union{MCTS_node,Nothing}
    children::Union{Nothing, Vector{MCTS_node}}
    total_weight_at_end::Float64
    visits::Int
    current_player::Symbol
    terminal::Bool
    last_move::Union{Nothing,Edge}
end

mutable struct ValueTracker
    Q_min::Float64
    Q_max::Float64
end

function MCTS(state::ExtendedGameState, orig_state::GameState; time_limit = 1.0)::Edge # state.graph muss die von short beanspruchten Kanten enthalten, WICHTIG: die Zusammenhangskomponenten von ComponentTracker müssen berichtigt werden, wenn der Anfangsgraph nicht-leer ist
    start_time = time()
    root_node = MCTS_node(nothing, Vector{MCTS_node}(), 0.0, 0, orig_state.current_player, false, nothing)
    s_component = get_component!(state.merged_graph.components, state.merged_graph.s.id)
    t_component = get_component!(state.merged_graph.components, state.merged_graph.t.id)
    tracker = ValueTracker(Inf, -Inf)
    short_graph = state.short_graph
    short_merged_graph = state.merged_graph

    save_base_state!(state.merged_graph.components)
    ws = DijkstraWorkspace(50)
    untried_actions = Vector{Edge}()
    untried_actions_at_root = valid_moves(orig_state)
    iterations = 0
    while true
        if time() - start_time >= time_limit
            break 
        end
        empty!(untried_actions)
        untried_actions = copy(untried_actions_at_root)
        root_node.visits += 1
        node = select(root_node, short_graph, short_merged_graph, untried_actions, tracker)
        if node.terminal
            backpropagate!(node, node.total_weight_at_end / (node.visits - 1), tracker, short_graph, short_merged_graph)
            restore_base_state!(state.merged_graph.components)
            iterations += 1
            continue
        end
        node = expand!(node, short_graph, short_merged_graph, untried_actions, ws)
        if node[2] != -1 # dann ist der expandierte Zustand ein Endzustand
            backpropagate!(node[1], node[2], tracker, short_graph, short_merged_graph)
            restore_base_state!(state.merged_graph.components)
            iterations += 1
            continue
        end
        weight = simulate!(node[1], short_graph, short_merged_graph, untried_actions, ws)
        backpropagate!(node[1], weight, tracker, short_graph, short_merged_graph)
        restore_base_state!(state.merged_graph.components)
        iterations += 1
    end
    println("Der Computer hat ", iterations, " viele Iterationen geschafft.")
    max_child = argmax(x -> x.visits, root_node.children)
    return max_child.last_move
end 

function select(node::MCTS_node, short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, tracker::ValueTracker)::MCTS_node
    current_node = node
    while !isempty(current_node.children)
        ucb = -Inf
        max_child = nothing
        found_node = false
        log_parent_visits = log(current_node.visits)
        is_short = current_node.current_player == :short
        span = tracker.Q_max - tracker.Q_min
        for child in current_node.children
            if child.visits == 0 # nur wichtig, wenn wir in einem Schritt mehrere Knoten expanden
                make_move!(short_graph, short_merged_graph, untried_actions, child.last_move, current_node.current_player)
                current_node = child
                found_node = true
                break
            end 

            exploration = sqrt(2.0 * log_parent_visits / child.visits)
            exploitation = child.total_weight_at_end / child.visits
            
            if span > 1e-8
                q_norm = (exploitation - tracker.Q_min) / span
            else
                q_norm = 0.5 # Neutraler Startwert, wenn alle Pfade noch denselben Wert haben
            end
 
            val = is_short ? -q_norm + exploration : q_norm + exploration
            if val > ucb
                max_child = child
                ucb = val
            end
        end
        if !found_node
            make_move!(short_graph, short_merged_graph, untried_actions, max_child.last_move, current_node.current_player)
            current_node = max_child
        end
        current_node.visits += 1
    end
    return current_node
end

function expand!(node::MCTS_node, short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, ws::DijkstraWorkspace)::Tuple{MCTS_node,Float64}
    new_node = nothing
    terminal = false
    idx = rand(1:length(untried_actions))
    next_move = untried_actions[idx]
    next_player = node.current_player == :short ? :cut : :short
    if length(untried_actions) > 1 # andernfalls wird unten schon der letzte mögliche Zustand eingefügt
        for i in 1:length(untried_actions)
            if i == idx
                continue
            end
            push!(node.children, MCTS_node(node, Vector{MCTS_node}(), 0.0, 0, next_player, false, untried_actions[i]))
        end
    end
    if node.current_player == :short
        make_move!(short_graph, short_merged_graph, untried_actions, idx, :short) # führe Zug auf übergebenen Bäumen aus #idx vlt
        terminal = isempty(untried_actions)
        if terminal
            weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
            new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 1, :cut, true, next_move)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 0, :cut, false, next_move)
        push!(node.children, new_node)
    elseif node.current_player == :cut # zunächst angenommen, dass cut random züge spielt
        make_move!(short_graph, short_merged_graph, untried_actions, idx, :cut)
        terminal = isempty(untried_actions)
        if terminal
            weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
            new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 1, :short, true, next_move)
            push!(node.children, new_node)
            return (new_node, weight)
        end 
        new_node = MCTS_node(node, Vector{MCTS_node}(), 0.0, 0, :short, false, next_move)
        push!(node.children, new_node)
    end
    new_node.visits += 1
    return (new_node,-1)
end

function simulate!(node::MCTS_node, short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, ws::DijkstraWorkspace)::Float64 # gibt das minimale Gewicht eines s-t-Weges zurück
    current_player = node.current_player
    simulated_moves = Tuple{Edge, Symbol}[] 
    while !isempty(untried_actions)
        idx = rand(1:length(untried_actions))
        push!(simulated_moves, (untried_actions[idx], current_player))
        make_move!(short_graph, short_merged_graph, untried_actions, idx, current_player)
        current_player = current_player == :short ? :cut : :short
    end
    weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
    for i in length(simulated_moves):-1:1
        move, player = simulated_moves[i]
        undo_move!(short_graph, short_merged_graph, move, player)
    end
    return weight
end

function backpropagate!(node::MCTS_node, weight_at_end::Float64, tracker::ValueTracker, short_graph::GameGraph, short_merged_graph::EfficientGameGraph)
    current_node = node
    while !isnothing(current_node) # wird immer mit mindestens Kindknoten von root aufgerufen
        current_node.total_weight_at_end += weight_at_end

        if current_node.visits > 0
            q_current = current_node.total_weight_at_end / current_node.visits
            if q_current < tracker.Q_min
                tracker.Q_min = q_current
            end
            if q_current > tracker.Q_max
                tracker.Q_max = q_current
            end
        end

        if !isnothing(current_node.parent)
            undo_move!(short_graph, short_merged_graph, current_node.last_move, current_node.parent.current_player)
        end
        
        current_node = current_node.parent
    end
end

function make_move!(short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, move::Edge, player::Symbol)
    if player == :short
        push!(short_graph.edges, move)
        merge_components!(short_merged_graph.components, move.u.id, move.v.id)
        delete!(short_merged_graph.edges, move)
        move_pos = findfirst(x -> x.id == move.id, untried_actions)
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    else
        delete!(short_merged_graph.edges, move)
        move_pos = findfirst(x -> x.id == move.id, untried_actions)
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    end
end

function make_move!(short_graph::GameGraph, short_merged_graph::EfficientGameGraph, untried_actions::Vector{Edge}, move_pos::Int, player::Symbol)
    if player == :short
        push!(short_graph.edges, untried_actions[move_pos]) 
        merge_components!(short_merged_graph.components, untried_actions[move_pos].u.id, untried_actions[move_pos].v.id)
        delete!(short_merged_graph.edges, untried_actions[move_pos])
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    else
        delete!(short_merged_graph.edges, untried_actions[move_pos])
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    end
end

function undo_move!(short_graph::GameGraph, short_merged_graph::EfficientGameGraph, move::Edge, player::Symbol)
    if player == :short
        pos = findfirst(x->x.id == move.id, short_graph.edges)
        short_graph.edges[pos] = short_graph.edges[end]
        pop!(short_graph.edges)
        push!(short_merged_graph.edges, move)
    else
        push!(short_merged_graph.edges, move)
    end
end

# -------------------------------------------------------------------------
# Alternative MCTS Implementierung für das Shannon Switching Game
# -------------------------------------------------------------------------

# Knoten-Struktur für den alternativen MCTS-Baum
# Knoten-Struktur für den alternativen MCTS-Baum
mutable struct MCTSNode3
    parent::Union{Nothing, MCTSNode3}
    move::Union{Nothing, Edge}
    player::Symbol               # Der Spieler, der IN DIESEM Knoten am Zug ist
    untried_moves::Vector{Edge}
    children::Vector{MCTSNode3}
    visits::Int
    total_score::Float64
end

# Workspace für schnelle, allokationsfreie Dijkstra-Durchläufe
struct DijkstraWorkspace3
    dist::Vector{Float64}
    visited::Vector{Bool}
end

# Simpler Array-basierter Dijkstra (O(V^2)) - sehr schnell für kleine bis mittlere Graphen
function dijkstra_3(graph::GameGraph, ws::DijkstraWorkspace3)::Float64
    fill!(ws.dist, Inf)
    fill!(ws.visited, false)
    
    ws.dist[graph.s.id] = 0.0
    
    for _ in 1:length(graph.vertices)
        min_d = Inf
        u = -1
        
        # Finde unbesuchten Knoten mit minimaler Distanz
        for v in graph.vertices
            id = v.id
            if !ws.visited[id] && ws.dist[id] < min_d
                min_d = ws.dist[id]
                u = id
            end
        end
        
        # Abbruch, wenn Ziel erreicht oder restlicher Graph unerreichbar
        if u == -1 || u == graph.t.id
            break
        end
        
        ws.visited[u] = true
        
        # Nachbarn updaten (betrachtet nur :short Kanten)
        for edge in graph.edges
            if edge.state == :short
                v_id = -1
                if edge.u.id == u
                    v_id = edge.v.id
                elseif edge.v.id == u
                    v_id = edge.u.id
                end
                
                if v_id != -1 && !ws.visited[v_id]
                    alt = min_d + edge.weight
                    if alt < ws.dist[v_id]
                        ws.dist[v_id] = alt
                    end
                end
            end
        end
    end
    
    return ws.dist[graph.t.id]
end

# UCB-Auswahl mit dynamischer Skalierung
function best_child_3(node::MCTSNode3, c_param::Float64)::MCTSNode3
    min_q = Inf
    max_q = -Inf
    
    # Lokale Min/Max Limits ermitteln für dynamische Skalierung
    for child in node.children
        if child.visits > 0
            q = child.total_score / child.visits
            min_q = min(min_q, q)
            max_q = max(max_q, q)
        end
    end
    
    span = max_q - min_q
    if span < 1e-8
        span = 1.0 # Verhindert Division durch 0
    end
    
    best_val = -Inf
    best_child = node.children[1] 
    log_n = log(node.visits)
    
    for child in node.children
        if child.visits == 0
            return child
        end
        
        q = child.total_score / child.visits
        q_norm = (q - min_q) / span
        
        # node.player bestimmt, wie der Wert bewertet wird
        if node.player == :short
            reward = 1.0 - q_norm  # Short will Distanz minimieren
        else
            reward = q_norm        # Cut will Distanz maximieren
        end
        
        ucb = reward + c_param * sqrt(log_n / child.visits)
        
        if ucb > best_val
            best_val = ucb
            best_child = child
        end
    end
    return best_child
end

# Führt ein Rollout bis zum Ende durch und bewertet es (Ohne externe Random-Abhängigkeit)
function rollout_3(graph::GameGraph, start_player::Symbol, ws::DijkstraWorkspace3)::Float64
    neutral_edges = [e for e in graph.edges if e.state == :neutral]
    
    # Manueller Fisher-Yates Shuffle (benötigt kein extra Random-Modul, nutzt Base.rand)
    n = length(neutral_edges)
    for i in n:-1:2
        j = rand(1:i)
        neutral_edges[i], neutral_edges[j] = neutral_edges[j], neutral_edges[i]
    end
    
    curr = start_player
    for e in neutral_edges
        e.state = curr
        curr = (curr == :short) ? :cut : :short
    end
    
    score = dijkstra_3(graph, ws)
    
    # Bestrafung, wenn Short keine Verbindung herstellen konnte
    if score == Inf
        score = 100_000.0 
    end
    
    # Rollout-Züge wieder aufräumen
    for e in neutral_edges
        e.state = :neutral
    end
    
    return score
end

# Der Kern der Tree-Policy (Selection -> Expansion -> Simulation -> Backpropagation)
function select_and_expand_3!(root::MCTSNode3, graph::GameGraph, ws::DijkstraWorkspace3)
    curr = root
    applied_moves = Edge[]
    
    # 1. Selection
    while isempty(curr.untried_moves) && !isempty(curr.children)
        curr = best_child_3(curr, 1.414)
        curr.move.state = curr.parent.player
        push!(applied_moves, curr.move)
    end
    
    # 2. Expansion
    if !isempty(curr.untried_moves)
        idx = rand(1:length(curr.untried_moves))
        move = curr.untried_moves[idx]
        
        # O(1) swap-and-pop für schnelles Löschen
        curr.untried_moves[idx] = curr.untried_moves[end]
        pop!(curr.untried_moves)
        
        move.state = curr.player
        push!(applied_moves, move)
        
        next_player = (curr.player == :short) ? :cut : :short
        
        # Dem neuen Knoten stehen alle aktuell neutralen Kanten zur Verfügung
        child_untried = [e for e in graph.edges if e.state == :neutral]
        
        child = MCTSNode3(curr, move, next_player, child_untried, MCTSNode3[], 0, 0.0)
        push!(curr.children, child)
        curr = child
    end
    
    # 3. Simulation
    score = rollout_3(graph, curr.player, ws)
    
    # 4. Backpropagation
    back_node = curr
    while back_node !== nothing
        back_node.visits += 1
        back_node.total_score += score
        back_node = back_node.parent
    end
    
    # Revert der Züge im echten Graph
    for m in applied_moves
        m.state = :neutral
    end
end

# Die Haupt-MCTS Routine
function mcts_search_3(state::GameState, time_limit::Float64)::Edge
    start_time = time()
    
    # Workspace initialisieren (Nimmt die maximal existierende Vertex-ID als Größe)
    max_id = maximum(v.id for v in state.graph.vertices)
    ws = DijkstraWorkspace3(Vector{Float64}(undef, max_id), Vector{Bool}(undef, max_id))
    
    neutral_edges = [e for e in state.graph.edges if e.state == :neutral]
    if isempty(neutral_edges)
        error("Keine gültigen Züge mehr möglich!")
    end
    
    root = MCTSNode3(nothing, nothing, state.current_player, copy(neutral_edges), MCTSNode3[], 0, 0.0)
    
    # Zeitlimit-Schleife
    while time() - start_time < time_limit
        select_and_expand_3!(root, state.graph, ws)
    end
    
    # Den meistbesuchten Knoten wählen (Robuster als den höchsten Average-Score)
    best_visits = -1
    best_move = nothing
    
    for child in root.children
        if child.visits > best_visits
            best_visits = child.visits
            best_move = child.move
        end
    end
    
    # Fallback, falls der Time_limit direkt greifen sollte
    if best_move === nothing
        best_move = rand(neutral_edges)
    end
    
    return best_move
end

# -------------------------------------------------------------------------
# Interface Funktionen für das Benchmark
# -------------------------------------------------------------------------

function weighted_short3(state::GameState; time_limit = 1.7)::Edge
    return @time mcts_search_3(state, time_limit)
end

function weighted_cut3(state::GameState; time_limit = 1.7)::Edge
    return @time mcts_search_3(state, time_limit)
end
const TEAM_NAME = "StockFisch 1.2"
const team_name = "StockFisch 1.2"
const punishment = 5000
Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

struct ComponentTracker
    parent::Vector{Int}
    size::Vector{Int}
    id_to_idx::Dict{Int, Int}
    idx_to_id::Vector{Int}

    ComponentTracker(p, s, id2idx, idx2id) = new(p, s, id2idx, idx2id)

    function ComponentTracker(vertex_ids::Vector{Int})
        n = length(vertex_ids)
        parent = collect(1:n)
        size = fill(1, n)
        
        
        id_to_idx = Dict{Int, Int}()
        sizehint!(id_to_idx, n)
        idx_to_id = Vector{Int}(undef, n)
    
        for (idx, id) in enumerate(vertex_ids)
            id_to_idx[id] = idx
            idx_to_id[idx] = id
        end
    
        return new(parent, size, id_to_idx, idx_to_id)
    end
end

mutable struct MinHeap
    elements::Vector{Tuple{Int,Float64}}
    size::Int
    position::Vector{Int} 
end

struct DijkstraWorkspace
    adj::Vector{Vector{Tuple{Int, Float64}}}
    dist::Vector{Float64}
    elems::Vector{Tuple{Int, Float64}}
    heap::MinHeap
end

mutable struct EfficientGameGraph
    edges::Base.Set{Edge}  
    components::ComponentTracker      #Short fügt hierin zusammen
    s::Vertex                 
    t::Vertex                 
end

mutable struct ExtendedGameState
    graph::EfficientGameGraph
    merged_graph::EfficientGameGraph
    short_graph::GameGraph
    A::Base.Set{Edge} 
    B::Base.Set{Edge} 
    e1::Edge
    e2::Edge
    has_winning_strategy::Symbol
    current_player::Symbol
    first_optimal_move::Bool 
    imaginary_moves::Base.Set{Edge}
    winner::Union{Symbol, Nothing}
end

mutable struct MCTS_node
    parent::Union{MCTS_node,Nothing}
    children::Union{Nothing, Vector{MCTS_node}}
    total_weight_at_end::Float64
    visits::Int
    current_player::Symbol
    terminal::Bool
    last_move::Union{Nothing,Edge}
    untried_actions::Union{Vector{Edge},Nothing}
end

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)

Base.copy(ct::ComponentTracker)::ComponentTracker = ComponentTracker(copy(ct.parent), copy(ct.size), copy(ct.id_to_idx), copy(ct.idx_to_id))

Base.copy(g::GameGraph)::GameGraph = GameGraph(copy(g.vertices), copy(g.edges), g.s, g.t)

Base.copy(g::EfficientGameGraph)::EfficientGameGraph = EfficientGameGraph(copy(g.edges), copy(g.components), g.s, g.t)

function d_copy(g::GameGraph)::GameGraph
    new_vertices = Vector{Vertex}()
    for vertex in g.vertices
        push!(new_vertices, Vertex(vertex.id))
    end
    new_edges = Vector{Edge}()
    for edge in g.edges
        push!(new_edges, Edge(edge.id, new_vertices[findfirst(x->x.id == edge.u.id, new_vertices)], new_vertices[findfirst(x->x.id == edge.v.id, new_vertices)], edge.weight, edge.state))
    end
    return GameGraph(new_vertices, new_edges, g.s, g.t)
end

function _find_idx!(ct::ComponentTracker, idx::Int)::Int
    if ct.parent[idx] == idx
        return idx
    end
    ct.parent[idx] = _find_idx!(ct, ct.parent[idx]) # Pfadkompression
    return ct.parent[idx]
end

function get_component!(ct::ComponentTracker, id::Int)::Int
    idx = ct.id_to_idx[id] 
    root_idx = _find_idx!(ct, idx)
    return ct.idx_to_id[root_idx]
end

function merge_components!(ct::ComponentTracker, u_id::Int, v_id::Int)
    u_idx = ct.id_to_idx[u_id]
    v_idx = ct.id_to_idx[v_id]
    
    root_u = _find_idx!(ct, u_idx)
    root_v = _find_idx!(ct, v_idx)
    
    if root_u != root_v
        if ct.size[root_u] < ct.size[root_v]
            root_u, root_v = root_v, root_u
        end
        ct.parent[root_v] = root_u
        ct.size[root_u] += ct.size[root_v]
    end
end

function check_st_connection(G::EfficientGameGraph)::Bool
    if get_component!(G.components, G.s.id) == get_component!(G.components, G.t.id)
        return true
    end
    temp_components = copy(G.components)
    for e in G.edges
        merge_components!(temp_components, e.u.id, e.v.id)
        if get_component!(temp_components, G.s.id) == get_component!(temp_components, G.t.id)
            return true
        end
    end    
    return false
end

function kruskal(G::EfficientGameGraph, minimal::Bool)::Base.Set{Edge}
    temp_components = copy(G.components)
    tree_edges = Base.Set{Edge}()  
    if minimal
        edges_to_process = sort(collect(G.edges), by = e -> e.weight)
    else
        edges_to_process = G.edges
    end 
    for e in edges_to_process
        root_u = get_component!(temp_components, e.u.id)
        root_v = get_component!(temp_components, e.v.id)
        if root_u != root_v
            push!(tree_edges, e) 
            merge_components!(temp_components, e.u.id, e.v.id)
        end
    end   
    return tree_edges
end

function gemeinsame_Sehnen(G::EfficientGameGraph, T1::Base.Set{Edge})::Base.Set{Edge}
    EdgesG = Base.Set{Edge}()
    for e in G.edges
        if (get_component!(G.components, e.u.id) != get_component!(G.components, e.v.id)) && e ∉ T1
            push!(EdgesG, e)
        end 
    end      
    return EdgesG
end

function FC(Sehne::Edge, Spannbaum::Base.Set{Edge}, components::ComponentTracker)::Base.Set{Edge} 
    start_root = get_component!(components, Sehne.u.id)
    target_root = get_component!(components, Sehne.v.id)
    
    adj = Dict{Int, Vector{Tuple{Int, Edge}}}() #Adjazenzliste der Form Key: Root-ID der Komponente -> Value: Liste von (Nachbar-Root-ID, Kante im Spannbaum)
    
    for e in Spannbaum # Diese Kante verbindet zwei verschiedene Komponenten, Wir fügen sie als Kante hinzu
        root_u = get_component!(components, e.u.id)
        root_v = get_component!(components, e.v.id)
        push!(get!(adj, root_u, Tuple{Int, Edge}[]), (root_v, e))  #bitte frag mich nichts zu get ;)
        push!(get!(adj, root_v, Tuple{Int, Edge}[]), (root_u, e))
    end

    # Pfadsuche mittels DFS  
    parent_map = Dict{Int, Tuple{Int, Edge}}() # Wir speichern: parent_node[node] = (predecessor_node, edge_that_connected_them)
    visited = Set{Int}([start_root])
    stack = [start_root]
    
    found = false
    while !isempty(stack)
        curr_root = pop!(stack)  

        if curr_root == target_root
            found = true
            break
        end
        
        for (neighbor_root, edge) in get(adj, curr_root, Tuple{Int, Edge}[])
            if neighbor_root ∉ visited
                push!(visited, neighbor_root)
                parent_map[neighbor_root] = (curr_root, edge)
                push!(stack, neighbor_root)
            end
        end
    end
    
    cycle = Base.Set{Edge}()
    if found
        # Rückverfolgung vom Ziel zum Start
        curr = target_root
        while curr != start_root
            prev_node, edge = parent_map[curr]
            push!(cycle, edge)
            curr = prev_node
        end
    end
    
    return cycle
end

function who_can_win(g::ExtendedGameState, minimal::Bool)
    T1_edges = kruskal(g.merged_graph, minimal)
    T2_edges = Base.copy(T1_edges)
    if minimal 
        Sehnen = sort(collect(gemeinsame_Sehnen(g.merged_graph, T1_edges)), by = e -> e.weight)
    else 
        Sehnen = collect(gemeinsame_Sehnen(g.merged_graph, T1_edges))
    end 
    e1 = g.e1
    e2 = g.e2  #ich hoffe im Wettbewerb gibt es keine Kanten mit Gewichten -1, -2; sonst ändern
    push!(Sehnen, e1, e2)
    i = 0
    n = length(Sehnen)
    while i < n && !isdisjoint(T1_edges, T2_edges)   #length(Sehnen) = j + 2 
        i += 1
        b = Sehnen[i]
        Layers = Vector{Base.Set{Edge}}()
        push!(Layers, Base.Set([b]))
        parent = Dict{Edge, Edge}()
        k=0
        while true
            k += 1
            T = (k % 2 == 1) ? T1_edges : T2_edges
            T_next = (k % 2 == 1) ? T2_edges : T1_edges
            new_set = Base.Set{Edge}()
            for elem ∈ Layers[k]
                fc = FC(elem, T, g.merged_graph.components)
                for elem2 ∈ fc
                    if !haskey(parent, elem2)
                        parent[elem2] = elem
                    end
                end
                union!(new_set, fc)
            end  
            push!(Layers, new_set)
            if k == 1
                if isempty(Layers[k+1]) 
                    break
                end
                S = intersect(Layers[k+1], T_next)
            else 
                if issetequal(Layers[k+1], Layers[k-1])
                    break
                end  
                S = intersect(setdiff(Layers[k+1], Layers[k-1]), T_next)
            end 
            if isempty(S)
                continue # dann ist der Augmentierungsschritt fehlgeschlagen
            end 
            bk = first(S) 
            while k > 0
                b_prev = parent[bk]
                delete!(T, bk)   
                push!(T, b_prev)
                bk = b_prev
                k -= 1
                T = (k % 2 == 1) ? T1_edges : T2_edges
            end 
            break 
        end
    end
    g.A = T1_edges
    g.B = T2_edges
    if e1 ∈ T2_edges || e2 ∈ T1_edges 
        g.has_winning_strategy = :cut
    elseif e1 ∈ T1_edges 
        g.has_winning_strategy = g.current_player
    else
        g.has_winning_strategy = :short
    end
end

function chase(g::ExtendedGameState, state::GameState)::Edge
    skip = false
    if g.first_optimal_move == true 
        if g.e1 ∈ g.A 
            last_move = g.e1  
        else 
            last_move = rand(setdiff(symdiff(g.A, g.B), [g.e1, g.e2])) #wie unten
            push!(g.imaginary_moves, last_move)
            skip = true 
        end 
        g.first_optimal_move = false
    else
        last_move = state.history[end][2]
    end 
    T1_has_move = (last_move ∈ g.A)
    T2_has_move = (last_move ∈ g.B)
    if (T1_has_move && T2_has_move) || (!T1_has_move && !T2_has_move) || last_move ∈ g.imaginary_moves || get_component!(g.merged_graph.components, last_move.u.id) == get_component!(g.merged_graph.components, last_move.v.id)
        if !skip
            last_move = rand(setdiff(symdiff(g.A, g.B), [g.e1, g.e2]))   
            push!(g.imaginary_moves, last_move)
        end
        T1_has_move = (last_move ∈ g.A)
        T2_has_move = !T1_has_move
    end 
    T = T1_has_move ? g.A : g.B
    T_strich = T2_has_move ? g.A : g.B
    if state.current_player == :cut 
        fc_last = FC(last_move, T_strich, g.merged_graph.components)
        next_move = nothing 
        for move in valid_moves(state)
            if move ∈ fc_last && last_move ∈ FC(move, T, g.merged_graph.components)
                next_move = move 
                break  
            end
        end
    else 
        fc_last = FC(last_move, T_strich, g.merged_graph.components)
        next_moves = Base.Set{Edge}()
        for move in valid_moves(state)
            if move ∈ fc_last && last_move ∈ FC(move, T, g.merged_graph.components) 
                push!(next_moves, move) 
            end
        end
        next_move = first(next_moves)
        for e in next_moves
            if e.weight < next_move.weight
                next_move = e
            end
        end
    end 
    T = (state.current_player == :cut) ? T_strich : T
    cut_move = (state.current_player == :cut) ? next_move : last_move
    short_move = (state.current_player == :cut) ? last_move : next_move
    delete!(T, cut_move)
    push!(T, short_move)
    return next_move
end

function min_heapify!(A::MinHeap, i::Int)
    while true
        l = 2 * i
        r = 2 * i + 1
        smallest = i
        if l ≤ A.size && A.elements[l][2] < A.elements[smallest][2]
            smallest = l
        end
        if r ≤ A.size && A.elements[r][2] < A.elements[smallest][2]
            smallest = r
        end
        smallest == i && break
        
        A.elements[i], A.elements[smallest] = A.elements[smallest], A.elements[i]
        A.position[A.elements[i][1]] = i
        A.position[A.elements[smallest][1]] = smallest
        i = smallest
    end
    return A
end

function extract_min!(A::MinHeap)  
    min_elem = A.elements[1]    
    
    A.elements[1] = A.elements[A.size]
    A.position[A.elements[1][1]] = 1    
    A.size -= 1   
    A.position[min_elem[1]] = 0    
    
    if A.size > 0
        min_heapify!(A, 1)
    end    
    return min_elem
end

function decrease_key!(A::MinHeap, i::Int, k::Float64)  
    A.elements[i] = (A.elements[i][1], k)   
    while i > 1
        parent = i ÷ 2
        if A.elements[parent][2] > A.elements[i][2]
            A.elements[i], A.elements[parent] = A.elements[parent], A.elements[i]
            A.position[A.elements[i][1]] = i
            A.position[A.elements[parent][1]] = parent            
            i = parent
        else
            break
        end
    end
end

function build_heap!(A::MinHeap, elems::AbstractVector{Tuple{Int,Float64}})
    A.size = length(elems)
    for i in 1:A.size
        id, weight = elems[i]
        A.elements[i] = (id, weight)
        A.position[id] = i
    end
    for i in (A.size ÷ 2):-1:1
        min_heapify!(A, i)
    end
end

function DijkstraWorkspace(max_nodes::Int = 70)
    adj = [Tuple{Int, Float64}[] for _ in 1:max_nodes]
    dist = fill(Inf, max_nodes)
    elems = Vector{Tuple{Int, Float64}}(undef, max_nodes)

    heap_elements = fill((0, 0.0), max_nodes)
    heap_position = fill(0, max_nodes)
    heap = MinHeap(heap_elements, 0, heap_position)
    
    return DijkstraWorkspace(adj, dist, elems, heap)
end

function dijkstra(g::GameGraph, s::Vertex, t::Vertex, ws::DijkstraWorkspace)::Float64
    max_id = isempty(g.vertices) ? 0 : maximum(v -> v.id, g.vertices)
    
    if max_id == 0
        return punishment
    end

    for i in 1:max_id
        empty!(ws.adj[i])
    end
    fill!(ws.dist, Inf)
    
    for e in g.edges
        push!(ws.adj[e.u.id], (e.v.id, e.weight))
        push!(ws.adj[e.v.id], (e.u.id, e.weight)) 
    end
    
    ws.dist[s.id] = 0.0

    num_vertices = length(g.vertices)
    for (i, vertex) in enumerate(g.vertices)
        ws.elems[i] = (vertex.id, ws.dist[vertex.id])
    end
    
    build_heap!(ws.heap, view(ws.elems, 1:num_vertices)) 
    
    while ws.heap.size > 0
        u_id, u_dist = extract_min!(ws.heap)
        
        if u_dist == Inf 
            break 
        end
        if u_id == t.id
            return u_dist
        end        
        
        for (v_id, weight) in ws.adj[u_id]
            new_dist = u_dist + weight           
            if new_dist < ws.dist[v_id]
                ws.dist[v_id] = new_dist                
                pos = ws.heap.position[v_id]
                if pos > 0 
                    decrease_key!(ws.heap, pos, new_dist)
                end
            end
        end
    end
    
    return punishment
end
########################################################################################################ENDE HILFSFUNKTIONEN##########################################################
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
        return MCTS(EXTENDED_STATE[], state, time_limit = 1.5 - (end_time - start_time))
    end 
    
    if EXTENDED_STATE[].has_winning_strategy == :cut
        cuts_edge = chase(EXTENDED_STATE[], state)
    else 
        merged_graph = EXTENDED_STATE[].merged_graph
        merge_components!(merged_graph.components, shorts_edge.u.id, shorts_edge.v.id)
        delete!(merged_graph.edges, shorts_edge)
        if (get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.t.id) || get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.t.id))
    
            EXTENDED_STATE[].winner = :short
            end_time = time()   
            return MCTS(EXTENDED_STATE[], state, time_limit = 1.5 - (end_time - start_time))
        end 
        who_can_win(EXTENDED_STATE[], false)
        if EXTENDED_STATE[].has_winning_strategy == :cut  
            EXTENDED_STATE[].first_optimal_move = true 
            cuts_edge = chase(EXTENDED_STATE[], state)
        else
            end_time = time()   
            cuts_edge = MCTS(EXTENDED_STATE[], state, time_limit = 1.5 - (end_time - start_time))
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
    shorts_edge = MCTS(EXTENDED_STATE[], state, time_limit = 1.5 - (end_time - start_time)) 
    return shorts_edge
end

function MCTS(state::ExtendedGameState, orig_state::GameState; time_limit = 1.0)::Edge 
    start_time = time()
    short_graph = state.short_graph

    max_id = isempty(orig_state.graph.vertices) ? 0 : maximum(v -> v.id, orig_state.graph.vertices)
    ws = DijkstraWorkspace(max(70, max_id + 5))

    untried_actions = Vector{Edge}()
    untried_actions_at_root = valid_moves(orig_state)
    sizehint!(untried_actions, length(untried_actions_at_root))
    root_node = MCTS_node(nothing, Vector{MCTS_node}(), 0.0, 0, orig_state.current_player, false, nothing, copy(untried_actions_at_root))
    max_moves = length(untried_actions_at_root)
    sim_buffer = Vector{Tuple{Edge, Symbol}}(undef, max_moves)
    
    iterations = 0

    while true
        iterations += 1
        if (iterations & 127) == 0 && time() - start_time >= time_limit  
            break 
        end
        empty!(untried_actions)
        append!(untried_actions, untried_actions_at_root)
        
        root_node.visits += 1
        node = select(root_node, short_graph, untried_actions)
        if node.terminal
            backpropagate(node, node.total_weight_at_end / (node.visits - 1), short_graph)
            continue
        end
        node = expand(node, short_graph, untried_actions, ws)
        if node[2] != -1 
            backpropagate(node[1], node[2], short_graph)
            continue
        end
        weight = simulate(node[1], short_graph, untried_actions, ws, sim_buffer)
        backpropagate(node[1], weight, short_graph)
    end
    max_child = argmax(x -> x.visits, root_node.children)
    return max_child.last_move
end

function select(node::MCTS_node, short_graph::GameGraph, untried_actions::Vector{Edge})::MCTS_node
    current_node = node
    while (current_node.untried_actions === nothing || isempty(current_node.untried_actions)) && current_node.children !== nothing && !isempty(current_node.children)
        local_q_min = Inf
        local_q_max = -Inf
        
        for child in current_node.children
            if child.visits > 0
                q = child.total_weight_at_end / child.visits
                if q < local_q_min
                    local_q_min = q
                end
                if q > local_q_max
                    local_q_max = q
                end
            end
        end

        span = local_q_max - local_q_min

        ucb = -Inf
        max_child = nothing
        found_node = false
        log_parent_visits = log(current_node.visits)
        is_short = current_node.current_player == :short
     
        for child in current_node.children
            if child.visits == 0 # nur wichtig, wenn wir in einem Schritt mehrere Knoten expanden
                make_move!(short_graph, untried_actions, child.last_move, current_node.current_player)
                current_node = child
                found_node = true
                break
            end 

            exploration = sqrt(2.0 * log_parent_visits / child.visits)
            exploitation = child.total_weight_at_end / child.visits
            
            if span > 1e-8
                q_norm = (exploitation - local_q_min) / span
            else
                q_norm = 0.5 # Neutraler Startwert, wenn alle Pfade (bisher) denselben Durchschnitt haben
            end
 
            if is_short
                val = (1.0 - q_norm) + exploration
            else
                val = q_norm + exploration
            end

            if val > ucb
                max_child = child
                ucb = val
            end
        end
        if !found_node
            make_move!(short_graph, untried_actions, max_child.last_move, current_node.current_player)
            current_node = max_child
        end
        current_node.visits += 1
    end
    return current_node
end

function expand(node::MCTS_node, short_graph::GameGraph, untried_actions::Vector{Edge}, ws::DijkstraWorkspace)::Tuple{MCTS_node,Float64}
    if node.untried_actions === nothing || isempty(node.untried_actions)
        return (node, dijkstra(short_graph, short_graph.s, short_graph.t, ws))
    end

    idx = rand(1:length(node.untried_actions))
    next_move = node.untried_actions[idx]
    node.untried_actions[idx] = node.untried_actions[end]
    pop!(node.untried_actions)

    next_player = node.current_player == :short ? :cut : :short
    make_move!(short_graph, untried_actions, next_move, node.current_player)
    child_untried = copy(untried_actions)
    terminal = isempty(child_untried)

    if node.children === nothing
        node.children = Vector{MCTS_node}()
    end
    
    if terminal
        weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
        new_node = MCTS_node(node, nothing, 0.0, 1, next_player, true, next_move, child_untried)
        push!(node.children, new_node)
        return (new_node, weight)
    else
        new_node = MCTS_node(node, nothing, 0.0, 1, next_player, false, next_move, child_untried)
        push!(node.children, new_node)
        return (new_node, -1.0)
    end
end

function simulate(node::MCTS_node, short_graph::GameGraph, untried_actions::Vector{Edge}, ws::DijkstraWorkspace, sim_buffer::Vector{Tuple{Edge, Symbol}})::Float64 
    current_player = node.current_player
    sim_count = 0

    while !isempty(untried_actions)
        idx = rand(1:length(untried_actions))
        sim_count += 1
        sim_buffer[sim_count] = (untried_actions[idx], current_player)
        make_move!(short_graph, untried_actions, idx, current_player)
        current_player = current_player == :short ? :cut : :short
    end
    weight = dijkstra(short_graph, short_graph.s, short_graph.t, ws)
    for i in sim_count:-1:1
        move, player = sim_buffer[i]
        undo_move!(short_graph, move, player)
    end
    return weight
end

function backpropagate(node::MCTS_node, weight_at_end::Float64, short_graph::GameGraph)
    current_node = node
    while !isnothing(current_node) # wird immer mit mindestens Kindknoten von root aufgerufen
        current_node.total_weight_at_end += weight_at_end

        if !isnothing(current_node.parent)
            undo_move!(short_graph, current_node.last_move, current_node.parent.current_player)
        end
        
        current_node = current_node.parent
    end
end

function make_move!(short_graph::GameGraph, untried_actions::Vector{Edge}, move_pos::Int, player::Symbol)
    if player == :short
        push!(short_graph.edges, untried_actions[move_pos]) 
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    else
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    end
end

function make_move!(short_graph::GameGraph, untried_actions::Vector{Edge}, move::Edge, player::Symbol)
    if player == :short
        push!(short_graph.edges, move)
        move_pos = findfirst(x -> x.id == move.id, untried_actions)
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    else
        move_pos = findfirst(x -> x.id == move.id, untried_actions)
        untried_actions[move_pos] = untried_actions[end]
        pop!(untried_actions)
    end
end

function undo_move!(short_graph::GameGraph, move::Edge, player::Symbol)
    if player == :short
        pos = findfirst(x->x.id == move.id, short_graph.edges)
        short_graph.edges[pos] = short_graph.edges[end]
        pop!(short_graph.edges)
    end
end
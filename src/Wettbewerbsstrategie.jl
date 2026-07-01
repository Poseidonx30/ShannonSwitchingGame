const TEAM_NAME::String = "StockFisch 1.0"

const punishment = 100.0

Base.isequal(E1::Edge, E2::Edge) = E1.id == E2.id # es gibt nicht zwei gleiche Kanten mit unterschiedlicher ID
Base.hash(E::Edge, h::UInt) = hash(E.id, h)

Base.hash(v::Vertex, h::UInt) = hash(v.id, h)
Base.isequal(v1::Vertex, v2::Vertex) = v1.id == v2.id

const EXTENDED_STATE = Ref{Union{Nothing, ExtendedGameState}}(nothing)


function weighted_cut(state::GameState)::Edge 
    if length(state.history) == 1 #Initialisieren vom Extended State
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(Vector{Vertex}(), Vector{Edge}(), state.graph.s, state.graph.t)
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Vector{Int}(), Vector{Int}(), Dict{Int, Int}(), Vector{Int}()), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :cut, false, Base.Set{Edge}(), nothing)
    end 
    if EXTENDED_STATE[].winner != :cut  #noch nicht gewonnen (im aktuellen merged graph, nicht allgemein)
        EXTENDED_STATE[].winner = (check_st_connection(EXTENDED_STATE[].merged_graph) == false) ? :cut : nothing
    end
    if EXTENDED_STATE[].winner == :cut  #schon gewonnen (im aktuellen merged graph sind s und t nicht mehr verbunden)
        return rand(valid_moves(state))
    end 

    if EXTENDED_STATE[].has_winning_strategy == :cut
        cuts_edge = chase(EXTENDED_STATE[], state)
    else 
        shorts_edge = state.history[end][2]
        merged_graph = EXTENDED_STATE[].merged_graph
        if !(get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.t.id) 
            || get_component!(merged_graph.components, shorts_edge.v.id) == get_component!(merged_graph.components, merged_graph.s.id) && get_component!(merged_graph.components, shorts_edge.u.id) == get_component!(merged_graph.components, merged_graph.t.id))
            merge_components!(merged_graph.components, shorts_edge.u.id, shorts_edge.v.id)  #neue Zusammenhangskomponenten setzen; s und t sollen nicht in einem Zshk. kommen
        end 
        delete!(merged_graph.edges, shorts_edge)
        who_can_win(EXTENDED_STATE[], false)
        if EXTENDED_STATE[].has_winning_strategy == :cut  #false, da für cut Gewichtung nicht interessant, falls optimale Strategie existiert (sofern Strafe für short hoch genug - hoffe ich mal)
            EXTENDED_STATE[].first_optimal_move = true 
            cuts_edge = chase(EXTENDED_STATE[], state)
        else
            println("hallo")
            cuts_edge = MCTS(state)
        end 
    end 
    delete!(EXTENDED_STATE[].merged_graph.edges, cuts_edge)
    return cuts_edge
end

function weighted_short(state::GameState)::Edge
    len = length(state.history)
    if len == 0 #Initialisieren vom Extended State
        e1 = Edge(-1, state.graph.s, state.graph.t, 0.0, :neutral)
        e2 = Edge(-2, state.graph.s, state.graph.t, 0.0, :neutral)
        short_graph = GameGraph(Vector{Vertex}(), Vector{Edge}(), state.graph.s, state.graph.t)
        graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker(Vector{Int}(), Vector{Int}(), Dict{Int, Int}(), Vector{Int}()), state.graph.s, state.graph.t) 
        merged_graph = EfficientGameGraph(Base.Set(state.graph.edges), ComponentTracker([v.id for v in state.graph.vertices]), state.graph.s, state.graph.t) 
        EXTENDED_STATE[] = ExtendedGameState(graph, merged_graph, short_graph, Base.Set{Edge}(), Base.Set{Edge}(), e1, e2, :neutral, :short, false, Base.Set{Edge}(), nothing)
    end 
    if len != 0 && EXTENDED_STATE[].winner != :cut  
        EXTENDED_STATE[].winner = (check_st_connection(EXTENDED_STATE[].merged_graph) == false) ? :cut : nothing
    end
    if EXTENDED_STATE[].winner == :cut  
        return rand(valid_moves(state))
    end
    shorts_edge = MCTS(state)
    merge_components!(EXTENDED_STATE[].merged_graph.components, shorts_edge.u.id, shorts_edge.v.id) 
    if len !=0
        delete!(EXTENDED_STATE[].merged_graph.edges, state.history[end][2])
    end
    return shorts_edge
end

#= mutable struct MCTS_node
    parent::Union{MCTS_node,Nothing}
    children::Base.Set{MCTS_node}
    total_weight_at_end::Float64
    visits::Int
    short_graph::GameGraph
    short_merged_graph::EfficientGameGraph
    current_player::Symbol
    terminal::Bool
    untried_actions::Base.Set{Edge} # der Wert gibt an, ob der Zug noch verfügbar ist
end

function MCTS(state::ExtendedGameState, orig_state::GameState; time_limit = 1.0)::Edge # state.graph muss die von short beanspruchten Kanten enthalten, WICHTIG: die Zusammenhangskomponenten von ComponentTracker müssen berichtigt werden, wenn der Anfangsgraph nicht-leer ist
    start_time = time()
    root_node = MCTS_node(nothing, Base.Set(), 0.0, 0, state.short_graph, state.merged_graph, :short, false, Base.Set(valid_moves(orig_state)))
    while true
        if time() - start_time >= time_limit
            println("Limit erreicht")
            break 
        end
        root_node.visits += 1
        node = select(root_node)
        if node.terminal
            backpropagate!(node, node.total_weight_at_end / node.visits)
        end
        new_node = expand!(node)
        if new_node[2] != -1 # dann ist der expandierte Zustand ein Endzustand
            println("weight: ", new_node[2])
            backpropagate!(new_node[1], new_node[2])
        end
        node = simulate!(new_node[1])
        println("weight: ", node[2])
        backpropagate!(node[1], node[2])
    end
    ucb = -Inf
    max_child = nothing
    for child in root_node.children
        if root_node.current_player == :short && child.visits != 0 && -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(root_node.visits)/child.visits)) > ucb
            max_child = child
            ucb = -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(root_node.visits)/child.visits))
        elseif root_node.current_player == :cut && child.visits != 0 && child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(root_node.visits)/child.visits) > ucb
            max_child = child
            ucb = child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(root_node.visits)/child.visits)
        end
    end
    return setdiff(max_child.parent.short_graph.edges, max_child.short_graph.edges)
end 

@inline function select(node::MCTS_node)::MCTS_node
    current_node = node
    # möglicherweise noch nicht besuchte Kinder bevorzugen
    while !isempty(current_node.children)
        ucb = -Inf
        max_child = nothing
        found_node = false
        for child in current_node.children
            if child.visits == 0 # nur wichtig, wenn wir in einem Schritt mehrere Knoten expanden
                current_node = child
                found_node = true
                break
            elseif current_node.current_player == :short && -child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits) > ucb # child.visits ≠ 0
                max_child = child
                ucb = -(child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits))
            elseif current_node.current_player == :cut && child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits) > ucb
                max_child = child
                ucb = child.total_weight_at_end/child.visits + sqrt(2) * sqrt(log(current_node.visits)/child.visits)
            end
        end
        if !found_node
            current_node = max_child
        end
        current_node.visits += 1
    end
    return current_node
end

@inline function expand!(node::MCTS_node)::Tuple{MCTS_node,Float64}
    new_node = nothing
    terminal = false
    println("Größe: ", length(collect(node.untried_actions)))
    if node.current_player == :short && get_component!(node.short_merged_graph.components, node.short_merged_graph.s.id) == get_component!(node.short_merged_graph.components, node.short_merged_graph.t.id) # dann haben wir schon einen s-t-Weg
        random_move = rand(collect(node.untried_actions)) # vielleicht noch nach Kantengewichten sortieren
        new_graph = copy(node.short_graph)
        push!(new_graph.edges, random_move)
        new_efficient_graph = copy(node.short_merged_graph)
        merge_components!(new_efficient_graph.components, random_move.u.id, random_move.v.id)
        new_untried_actions = Base.setdiff(node.untried_actions, [random_move])
        terminal = isempty(new_untried_actions)
        if terminal
            weight = dijkstra(node.graph, node.s, node.t)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, true, new_untried_actions)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, false, new_untried_actions)
        push!(node.children, new_node)
    elseif node.current_player == :short # wir suchen einen Zug, der zwei neue Zusammenhangskomponenten verbindet
        next_move = nothing
        for edge in node.untried_actions
            if get_component!(node.short_merged_graph.components, edge.u.id) != get_component!(node.short_merged_graph.components, edge.v.id) # falls die Kante zwei neue Zusammenhangskomponente verbindet # get_component!(node.short_merged_graph.components, node.graph.s.id) == get_component!(node.short_merged_graph.components, edge.u.id) && 
                next_move = edge
                break
            end
        end
        new_graph = copy(node.short_graph)
        push!(new_graph.edges, next_move)
        new_efficient_graph = copy(node.short_merged_graph)
        merge_components!(new_efficient_graph.components, next_move.u.id, next_move.v.id)
        new_untried_actions = Base.setdiff(node.untried_actions, [next_move])
        terminal = isempty(new_untried_actions)
        if terminal
            weight = dijkstra(node.graph, node.s, node.t)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, true, new_untried_actions)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, false, new_untried_actions)
        push!(node.children, new_node)
    elseif node.current_player == :cut # zunächst angenommen, dass cut random züge spielt
        # vielleicht noch optimieren, dass wenn s und t nicht in unterschiedlichen Zusammenhangskomponenten sind, das Spiel vorzeitig terminiert (short kassiert sowieso die Strafe)
        random_move = rand(collect(node.untried_actions))
        new_untried_actions = Base.setdiff(node.untried_actions, [random_move])
        terminal = isempty(new_untried_actions)
        if terminal
            weight = dijkstra(node.graph, node.s, node.t)
            new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, copy(node.short_graph), copy(node.short_merged_graph), :short, true, new_untried_actions)
            push!(node.children, new_node)
            return (new_node, weight)
        end
        new_node = MCTS_node(node, Base.Set{MCTS_node}(), 0.0, 0, copy(node.short_graph), copy(node.short_merged_graph), :short, false, new_untried_actions)
        push!(node.children, new_node)
    end
    new_node.visits += 1
    return (new_node,-1)
end

@inline function simulate!(node::MCTS_node)::Tuple{MCTS_node,Float64} # gibt den teminalen Knoten zurück sowie das minimale Gewicht eines s-t-Weges
    current_node = node
    while !current_node.terminal
        new_node = nothing
        if current_node.current_player == :short
            random_move = rand(collect(current_node.untried_actions))
            new_graph = copy(current_node.short_graph)
            push!(new_graph.edges, random_move)
            new_efficient_graph = copy(current_node.short_merged_graph)
            merge_components!(new_efficient_graph.components, random_move.u.id, random_move.v.id)
            new_untried_actions = Base.setdiff(current_node.untried_actions, [random_move])
            terminal = isempty(new_untried_actions)
            new_node = MCTS_node(current_node, Base.Set{MCTS_node}(), 0.0, 0, new_graph, new_efficient_graph, :cut, terminal, new_untried_actions)
            push!(current_node.children, new_node)
        else
            random_move = rand(collect(current_node.untried_actions))
            new_untried_actions = Base.setdiff(current_node.untried_actions, [random_move])
            terminal = isempty(new_untried_actions)
            new_node = MCTS_node(current_node, Base.Set{MCTS_node}(), 0.0, 0, copy(current_node.short_graph), copy(current_node.short_merged_graph), :short, terminal, new_untried_actions)
            push!(current_node.children, new_node)
        end
        current_node = new_node
        current_node.visits += 1
    end
    return (current_node, dijkstra(current_node.short_graph, current_node.short_graph.s, current_node.short_graph.t))
end

@inline function backpropagate!(node::MCTS_node, weight_at_end::Float64)
    current_node = node
    while !isnothing(current_node.parent) # wird immer mit mindestens Kindknoten von root aufgerufen
        current_node.total_weight_at_end += weight_at_end
        current_node = current_node.parent
    end
end
 =#
########################################################################################################

# Die Struct bleibt größtenteils gleich, aber untried_actions muss sauber 
# als "noch nicht als MCTS-Kindknoten erstellte Züge" verstanden werden.
mutable struct MCTS_node
    parent::Union{MCTS_node, Nothing}
    children::Vector{MCTS_node} # Vector ist oft schneller zu durchlaufen als Set
    total_weight_at_end::Float64
    visits::Int
    short_graph::GameGraph
    short_merged_graph::EfficientGameGraph
    current_player::Symbol
    terminal::Bool
    
    # Züge, die IN DIESEM ZUSTAND möglich sind, für die aber noch 
    # kein Kind-Knoten im Baum existiert.
    untried_actions::Base.Set{Edge} 
    
    # Alle Züge, die im Spiel ab diesem Knoten noch legal/frei sind.
    # Wichtig für die Weitergabe an die Kinder.
    legal_moves::Base.Set{Edge} 
end

function MCTS(orig_state::GameState; time_limit = 1.0)::Edge 
    start_time = time()
    legal_moves = Base.Set(valid_moves(orig_state))
    
    root_node = MCTS_node(
        nothing, MCTS_node[], 0.0, 0, 
        orig_state.short_graph, orig_state.merged_graph, 
        :short, false, 
        copy(legal_moves), copy(legal_moves)
    )

    while time() - start_time < time_limit
        # 1. SELECT
        node = select_node(root_node)
        
        # 2. EXPAND
        if !node.terminal
            node = expand!(node)
        end
        
        # 3. SIMULATE
        weight = simulate(node)
        
        # 4. BACKPROPAGATE
        backpropagate!(node, weight)
    end

    # Zugauswahl am Ende: Wähle das Kind mit den meisten Visits (Standard bei MCTS)
    best_child = argmax(child -> child.visits, root_node.children)
    
    # Finde heraus, welche Kante zu diesem Kind geführt hat
    # (Einfacher Set-Unterschied der Graphen)
    return first(setdiff(best_child.short_graph.edges, root_node.short_graph.edges))
end 

# ==========================================
# 1. SELECT
# ==========================================
function select_node(node::MCTS_node)::MCTS_node
    current_node = node
    # Solange der Knoten vollständig expandiert ist UND nicht terminal
    while isempty(current_node.untried_actions) && !current_node.terminal
        # Wähle das beste Kind basierend auf der UCB1-Formel
        best_score = -Inf
        best_child = nothing
        
        for child in current_node.children
            if child.visits == 0
                return child # Sollte theoretisch nicht passieren, aber als Fallback
            end
            
            mean_weight = child.total_weight_at_end / child.visits
            exploration = sqrt(2) * sqrt(log(current_node.visits) / child.visits)
            
            # WICHTIG: Die Perspektive ist die des current_node!
            if current_node.current_player == :short
                # Short sucht den KÜRZESTEN Weg, will also das Gewicht MINIMIEREN.
                # Um das Maximum zu finden, maximieren wir den negativen Wert.
                score = -mean_weight + exploration
            else
                # Cut will das Gewicht MAXIMIEREN.
                score = mean_weight + exploration
            end
            
            if score > best_score
                best_score = score
                best_child = child
            end
        end
        current_node = best_child
    end
    return current_node
end

# ==========================================
# 2. EXPAND
# ==========================================
function expand!(node::MCTS_node)::MCTS_node
    # Wähle eine noch nicht probierte Aktion und entferne sie aus den untried_actions
    action = rand(node.untried_actions)
    delete!(node.untried_actions, action)
    
    # Kopiere den Graphenzustand für den NEUEN Kindknoten
    new_graph = copy(node.short_graph)
    new_efficient_graph = copy(node.short_merged_graph)
    
    if node.current_player == :short
        push!(new_graph.edges, action)
        merge_components!(new_efficient_graph.components, action.u.id, action.v.id)
    end
    
    # Aktualisiere die noch im Spiel verfügbaren Züge
    new_legal_moves = copy(node.legal_moves)
    delete!(new_legal_moves, action)
    is_terminal = isempty(new_legal_moves)
    
    next_player = node.current_player == :short ? :cut : :short
    
    # Erstelle das neue Kind
    new_node = MCTS_node(
        node, MCTS_node[], 0.0, 0, 
        new_graph, new_efficient_graph, 
        next_player, is_terminal, 
        copy(new_legal_moves), new_legal_moves
    )
    
    push!(node.children, new_node)
    return new_node
end

# ==========================================
# 3. SIMULATE
# ==========================================
function simulate(node::MCTS_node)::Float64
    # GANZ WICHTIG: Nur eine EINZIGE Kopie für die gesamte Simulation ziehen, 
    # KEINE neuen MCTS_Knoten erstellen! Das spart massiv RAM und Zeit.
    sim_graph = copy(node.short_graph)
    sim_efficient = copy(node.short_merged_graph)
    sim_legal_moves = collect(node.legal_moves) # Vector für O(1) random access & delete
    
    current_player = node.current_player
    
    while !isempty(sim_legal_moves)
        # Zufälligen Zug auswählen
        idx = rand(1:length(sim_legal_moves))
        action = sim_legal_moves[idx]
        
        # Effizient aus dem Array löschen (tauscht das letzte Element an idx und macht pop)
        sim_legal_moves[idx] = sim_legal_moves[end]
        pop!(sim_legal_moves)
        
        if current_player == :short
            push!(sim_graph.edges, action)
            merge_components!(sim_efficient.components, action.u.id, action.v.id)
            
            # Early Exit: Wenn s und t verbunden sind, ist das Spiel sofort vorbei!
            if get_component!(sim_efficient.components, sim_graph.s.id) == get_component!(sim_efficient.components, sim_graph.t.id)
                break 
            end
        end
        
        current_player = current_player == :short ? :cut : :short
    end
    
    weight = dijkstra(sim_graph, sim_graph.s, sim_graph.t)
    # Strafpunkte, falls kein Weg existiert (Dijkstra gibt vermutlich Inf zurück)
    return weight == Inf ? 100.0 : weight 
end

# ==========================================
# 4. BACKPROPAGATE
# ==========================================
function backpropagate!(node::MCTS_node, weight::Float64)
    current = node
    while !isnothing(current)
        current.visits += 1
        current.total_weight_at_end += weight
        current = current.parent
    end
end
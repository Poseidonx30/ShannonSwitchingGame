#Devrim Firat Yilmaz
using Gtk4
using Cairo
#Um das Spiel zu starten:
#julia --project=. -e 'using ShannonSwitchingGame; run_gui()'
# Diese Datei enthält nur die GUI. Die eigentliche Spiellogik steht in game.jl.
# Wichtig: Beim Laden des Pakets wird noch kein Fenster erzeugt. Das passiert
# erst, wenn run_gui() aufgerufen wird.

const NODE_RADIUS = 20.0
const CLICK_DISTANCE = 16.0

"""
    run_gui()

Startet das grafische Shannon-Switching-Spiel. Die Funktion baut das Fenster,
legt alle Buttons und Eingabefelder an und verbindet die Klicks mit der
Spiellogik aus `game.jl`.

# Beispiel
```julia
julia> using ShannonSwitchingGame
julia> run_gui()
```
"""
function run_gui()
    current_graph = Ref{Union{Nothing, GameGraph}}(nothing)
    current_game_state = Ref{Union{Nothing, GameState}}(nothing)
    short_player_name = Ref("Short")
    cut_player_name = Ref("Cut")

    # -----------------------------------------------------------------------
    # Fenster und Bedienelemente
    # -----------------------------------------------------------------------

    win = GtkWindow("Shannon-Switching-Spiel", 1024, 768)
    Gtk4.maximize(win)

    main_box = GtkBox(:v)
    main_box.spacing = 10
    main_box.margin_top = 10
    main_box.margin_bottom = 10
    main_box.margin_start = 10
    main_box.margin_end = 10

    controls = GtkBox(:h)
    controls.spacing = 8

    name_controls = GtkBox(:h)
    name_controls.spacing = 8

    entry_n = GtkEntry()
    entry_n.placeholder_text = "Knoten n"
    entry_n.hexpand = true

    entry_m = GtkEntry()
    entry_m.placeholder_text = "Kanten m"
    entry_m.hexpand = true

    mode_choice = GtkDropDown(["2 Menschen", "Gegen den Computer"])
    Gtk4.selected!(mode_choice, 1)

    role_choice = GtkDropDown(["Ich spiele Short", "Ich spiele Cut"])
    Gtk4.selected!(role_choice, 1)
    role_choice.sensitive = false

    btn_new_game = GtkButton("Neues Spiel")
    btn_undo = GtkButton("Kante zurücknehmen")

    entry_short_name = GtkEntry()
    entry_short_name.placeholder_text = "Spieler 1 (Short)"
    entry_short_name.hexpand = true

    entry_cut_name = GtkEntry()
    entry_cut_name.placeholder_text = "Spieler 2 / Computer (Cut)"
    entry_cut_name.hexpand = true

    push!(controls, entry_n)
    push!(controls, entry_m)
    push!(controls, mode_choice)
    push!(controls, role_choice)
    push!(controls, btn_new_game)
    push!(controls, btn_undo)

    push!(name_controls, entry_short_name)
    push!(name_controls, entry_cut_name)

    turn_label = GtkLabel("Am Zug: -")
    turn_label.halign = Gtk4.Align_START

    status_label = GtkLabel("Bitte n, m und beide Namen eingeben und ein neues Spiel starten.")
    status_label.halign = Gtk4.Align_START

    canvas = GtkCanvas()
    canvas.hexpand = true
    canvas.vexpand = true

    history_box = GtkBox(:v)
    history_box.spacing = 6
    history_box.vexpand = true
    history_box.width_request = 260

    history_title = GtkLabel("Züge")
    history_title.halign = Gtk4.Align_START

    history_label = GtkLabel("-")
    history_label.halign = Gtk4.Align_START
    history_label.valign = Gtk4.Align_START
    history_label.wrap = true

    history_scroll = GtkScrolledWindow()
    history_scroll.vexpand = true
    history_scroll.hexpand = false
    history_scroll.width_request = 260
    history_scroll[] = history_label

    push!(history_box, history_title)
    push!(history_box, history_scroll)

    game_area = GtkBox(:h)
    game_area.spacing = 10
    game_area.hexpand = true
    game_area.vexpand = true
    push!(game_area, canvas)
    push!(game_area, history_box)

    push!(main_box, controls)
    push!(main_box, name_controls)
    push!(main_box, turn_label)
    push!(main_box, status_label)
    push!(main_box, game_area)
    win.child = main_box

    # -----------------------------------------------------------------------
    # Kleine Hilfsfunktionen
    # -----------------------------------------------------------------------

    """
        is_computer_game()

    Prüft, ob in der GUI der Modus "Gegen den Computer" ausgewählt ist.

    # Beispiel
    ```julia
    julia> is_computer_game()
    false
    ```
    """
    is_computer_game() = Gtk4.selected(mode_choice) == 2

    """
        human_player()

    Gibt zurück, welche Rolle der Mensch im Computer-Modus spielt:
    `:short` oder `:cut`.

    # Beispiel
    ```julia
    julia> human_player()
    :short
    ```
    """
    human_player() = Gtk4.selected(role_choice) == 1 ? :short : :cut

    """
        computer_player()

    Gibt die Rolle des Computers zurück. Der Computer spielt immer die andere
    Rolle als der Mensch.

    # Beispiel
    ```julia
    julia> computer_player()
    :cut
    ```
    """
    computer_player() = human_player() == :short ? :cut : :short

    """
        is_computer_turn(state::GameState)

    Prüft, ob im aktuellen Spielzustand gerade der Computer am Zug ist.

    # Beispiel
    ```julia
    julia> is_computer_turn(state)
    true
    ```
    """
    is_computer_turn(state::GameState) = is_computer_game() && state.current_player == computer_player()

    """
        update_name_fields_for_mode!()

    Aktualisiert die Namensfelder passend zum Spielmodus. Im Computer-Modus
    wird der Computername fest auf `"Computer"` gesetzt und das Feld gesperrt.

    # Beispiel
    ```julia
    julia> update_name_fields_for_mode!()
    ```
    """
    function update_name_fields_for_mode!()
        role_choice.sensitive = is_computer_game()

        if !is_computer_game()
            entry_short_name.sensitive = true
            entry_cut_name.sensitive = true
            entry_short_name.placeholder_text = "Spieler 1 (Short)"
            entry_cut_name.placeholder_text = "Spieler 2 (Cut)"
            return
        end

        if human_player() == :short
            entry_short_name.sensitive = true
            entry_cut_name.sensitive = false
            entry_short_name.placeholder_text = "Dein Name (Short)"
            entry_cut_name.placeholder_text = "Computer (Cut)"
            Gtk4.text(entry_cut_name, "Computer")
        else
            entry_short_name.sensitive = false
            entry_cut_name.sensitive = true
            entry_short_name.placeholder_text = "Computer (Short)"
            entry_cut_name.placeholder_text = "Dein Name (Cut)"
            Gtk4.text(entry_short_name, "Computer")
        end
    end

    """
        player_name(player::Symbol)::String

    Liefert den angezeigten Namen zu einer Rolle. `:short` und `:cut` werden
    dadurch in echte Spielernamen wie `"Max"` oder `"Computer"` übersetzt.

    # Beispiel
    ```julia
    julia> player_name(:short)
    "Max"
    ```
    """
    function player_name(player::Symbol)::String
        player == :short && return short_player_name[]
        return cut_player_name[]
    end

    """
        set_status!(text::String)

    Schreibt eine Meldung in die Statuszeile der GUI.

    # Beispiel
    ```julia
    julia> set_status!("Max ist am Zug.")
    ```
    """
    function set_status!(text::String)
        status_label.label = text
    end

    """
        update_turn_label!()

    Aktualisiert die feste Anzeige links oben, zum Beispiel `"Am Zug: Max"`.

    # Beispiel
    ```julia
    julia> update_turn_label!()
    ```
    """
    function update_turn_label!()
        state = current_game_state[]
        if state === nothing
            turn_label.label = "Am Zug: -"
        elseif state.winner !== nothing
            turn_label.label = "Spiel beendet: $(player_name(state.winner)) gewinnt."
        else
            turn_label.label = "Am Zug: $(player_name(state.current_player))"
        end
    end

    """
        vertex_name(vertex::Vertex, graph::GameGraph)::String

    Gibt den Namen eines Knotens für die Anzeige zurück. Die Start- und
    Zielknoten heißen `"s"` und `"t"`, alle anderen Knoten behalten ihre ID.

    # Beispiel
    ```julia
    julia> vertex_name(graph.s, graph)
    "s"
    ```
    """
    function vertex_name(vertex::Vertex, graph::GameGraph)::String
        vertex === graph.s && return "s"
        vertex === graph.t && return "t"
        return string(vertex.id)
    end

    """
        edge_name(edge::Edge, graph::GameGraph)::String

    Erstellt den kurzen Anzeigenamen einer Kante, zum Beispiel `"s-3"`.

    # Beispiel
    ```julia
    julia> edge_name(edge, graph)
    "s-3"
    ```
    """
    function edge_name(edge::Edge, graph::GameGraph)::String
        return "$(vertex_name(edge.u, graph))-$(vertex_name(edge.v, graph))"
    end

    """
        move_name(player::Symbol, edge::Edge, graph::GameGraph)::String

    Formatiert einen Zug für die History-Liste rechts im Fenster.

    # Beispiel
    ```julia
    julia> move_name(:short, edge, graph)
    "Max: s-3"
    ```
    """
    function move_name(player::Symbol, edge::Edge, graph::GameGraph)::String
        return "$(player_name(player)): $(edge_name(edge, graph))"
    end

    """
        update_history!()

    Schreibt alle bisher gespielten Züge in die rechte Zugliste. Zwei Halbzüge
    werden wie beim Schach in einer nummerierten Zeile zusammengefasst.

    # Beispiel
    ```julia
    julia> update_history!()
    ```
    """
    function update_history!()
        state = current_game_state[]
        if state === nothing || isempty(state.history)
            history_label.label = "-"
            return
        end

        lines = String[]
        move_number = 1

        for i in 1:2:length(state.history)
            player1, edge1 = state.history[i]
            line = "$(move_number). $(move_name(player1, edge1, state.graph))"

            if i + 1 <= length(state.history)
                player2, edge2 = state.history[i + 1]
                line *= "    $(move_name(player2, edge2, state.graph))"
            end

            push!(lines, line)
            move_number += 1
        end

        history_label.label = join(lines, "\n")
    end

    """
        update_status!()

    Aktualisiert die Statusmeldung unter der Zuganzeige. Dort steht zum Beispiel,
    ob ein Spiel gestartet werden muss, wer am Zug ist oder wer gewonnen hat.

    # Beispiel
    ```julia
    julia> update_status!()
    ```
    """
    function update_status!()
        state = current_game_state[]
        if state === nothing
            set_status!("Bitte n, m und beide Namen eingeben und ein neues Spiel starten.")
        elseif is_computer_turn(state)
            set_status!("$(player_name(state.current_player)) ist am Zug. Klicke auf eine freie Kante.")
        else
            set_status!("$(player_name(state.current_player)) ist am Zug. Klicke auf eine freie Kante.")
        end
    end

    """
        refresh!()

    Aktualisiert alle sichtbaren Teile der GUI: Zuganzeige, Status, History und
    das gezeichnete Spielfeld.

    # Beispiel
    ```julia
    julia> refresh!()
    ```
    """
    function refresh!()
        update_turn_label!()
        update_status!()
        update_history!()
        Gtk4.draw(canvas)
    end

    """
        node_positions(graph::GameGraph, w::Real, h::Real)

    Berechnet die Positionen aller Knoten auf einem Kreis. Dadurch bleibt die
    Darstellung einfach und unabhängig von der Knotenzahl.

    # Beispiel
    ```julia
    julia> positions = node_positions(graph, 800, 600)
    julia> positions[graph.s.id]
    (704.0, 300.0)
    ```
    """
    function node_positions(graph::GameGraph, w::Real, h::Real)
        positions = Dict{Int, Tuple{Float64, Float64}}()
        n = length(graph.vertices)
        n == 0 && return positions

        center_x = w / 2
        center_y = h / 2
        radius = min(w, h) * 0.38

        for (i, vertex) in enumerate(graph.vertices)
            angle = (i - 1) * (2pi / n)
            positions[vertex.id] = (center_x + radius * cos(angle),
                                    center_y + radius * sin(angle))
        end

        return positions
    end

    """
        edge_key(edge::Edge)

    Gibt einen richtungsunabhängigen Schlüssel für eine Kante zurück. Damit
    werden Doppelkanten zwischen denselben Knoten gemeinsam erkannt.

    # Beispiel
    ```julia
    julia> edge_key(edge)
    (2, 5)
    ```
    """
    function edge_key(edge::Edge)
        a = min(edge.u.id, edge.v.id)
        b = max(edge.u.id, edge.v.id)
        return (a, b)
    end

    """
        all_known_edges(state::GameState)::Vector{Edge}

    Gibt alle Kanten zurück, die für die Darstellung bekannt sein müssen.
    Auch bereits von Cut entfernte Kanten werden aus der History gelesen, damit
    parallele Kanten stabil gekrümmt bleiben.

    # Beispiel
    ```julia
    julia> edges = all_known_edges(state)
    julia> length(edges)
    9
    ```
    """
    function all_known_edges(state::GameState)::Vector{Edge}
        # Cut entfernt Kanten aus graph.edges. Für stabile Parallelkurven nehmen
        # wir sie aus der Historie trotzdem in die Berechnung der Abstände auf.
        edges = copy(state.graph.edges)
        ids = Set(edge.id for edge in edges)

        for (_, edge) in state.history
            if edge.id ∉ ids
                push!(edges, edge)
                push!(ids, edge.id)
            end
        end

        sort!(edges, by = edge -> edge.id)
        return edges
    end

    """
        parallel_offsets(edges::Vector{Edge})::Dict{Int, Float64}

    Berechnet für parallele Kanten verschiedene Kurvenabstände. So liegen
    Doppelkanten nicht aufeinander, sondern werden symmetrisch gezeichnet.

    # Beispiel
    ```julia
    julia> offsets = parallel_offsets(graph.edges)
    julia> offsets[1]
    -17.0
    ```
    """
    function parallel_offsets(edges::Vector{Edge})::Dict{Int, Float64}
        groups = Dict{Tuple{Int, Int}, Vector{Edge}}()

        for edge in edges
            push!(get!(() -> Edge[], groups, edge_key(edge)), edge)
        end

        offsets = Dict{Int, Float64}()
        for group in values(groups)
            sort!(group, by = edge -> edge.id)
            n = length(group)

            for (i, edge) in enumerate(group)
                offsets[edge.id] = n == 1 ? 0.0 : (i - (n + 1) / 2) * 34.0
            end
        end

        return offsets
    end

    """
        visual_offset(edge::Edge, offsets)::Float64

    Korrigiert den Kurvenabstand für Kanten, deren Endpunkte intern andersherum
    gespeichert sind. Dadurch bleiben parallele Kanten wirklich symmetrisch.

    # Beispiel
    ```julia
    julia> visual_offset(edge, offsets)
    17.0
    ```
    """
    function visual_offset(edge::Edge, offsets)::Float64
        offset = get(offsets, edge.id, 0.0)

        # Die Kurvenrichtung muss für alle Kanten zwischen demselben Knotenpaar
        # gleich definiert sein. Wenn eine Kante intern andersherum gespeichert
        # ist, drehen wir deshalb das Vorzeichen um.
        return edge.u.id <= edge.v.id ? offset : -offset
    end

    """
        curve_control_point(x1, y1, x2, y2, offset)

    Berechnet den Kontrollpunkt für eine gekrümmte Kante. Der Kontrollpunkt
    liegt seitlich neben der geraden Verbindung.

    # Beispiel
    ```julia
    julia> curve_control_point(0, 0, 10, 0, 20)
    (5.0, 20.0)
    ```
    """
    function curve_control_point(x1, y1, x2, y2, offset)
        dx = x2 - x1
        dy = y2 - y1
        len = hypot(dx, dy)

        if len == 0
            return (x1, y1)
        end

        nx = -dy / len
        ny = dx / len
        return ((x1 + x2) / 2 + nx * offset, (y1 + y2) / 2 + ny * offset)
    end

    """
        point_on_curve(x1, y1, cx, cy, x2, y2, t)

    Berechnet einen Punkt auf einer quadratischen Kurve. Diese Funktion wird
    für die Klickerkennung auf gekrümmten Kanten verwendet.

    # Beispiel
    ```julia
    julia> point_on_curve(0, 0, 5, 10, 10, 0, 0.5)
    (5.0, 5.0)
    ```
    """
    function point_on_curve(x1, y1, cx, cy, x2, y2, t)
        a = (1 - t)^2
        b = 2 * (1 - t) * t
        c = t^2
        return (a * x1 + b * cx + c * x2, a * y1 + b * cy + c * y2)
    end

    """
        distance_to_edge(px, py, x1, y1, x2, y2)

    Berechnet den kleinsten Abstand eines Klickpunkts zu einer geraden Kante.

    # Beispiel
    ```julia
    julia> distance_to_edge(5, 2, 0, 0, 10, 0)
    2.0
    ```
    """
    function distance_to_edge(px, py, x1, y1, x2, y2)
        dx = x2 - x1
        dy = y2 - y1

        if dx == 0 && dy == 0
            return hypot(px - x1, py - y1)
        end

        # Projektion des Klicks auf die Strecke zwischen den beiden Knoten.
        t = ((px - x1) * dx + (py - y1) * dy) / (dx^2 + dy^2)
        t = clamp(t, 0.0, 1.0)
        nearest_x = x1 + t * dx
        nearest_y = y1 + t * dy

        return hypot(px - nearest_x, py - nearest_y)
    end

    """
        distance_to_drawn_edge(px, py, x1, y1, x2, y2, offset)

    Berechnet den Abstand eines Klickpunkts zu der tatsächlich gezeichneten
    Kante. Bei Doppelkanten ist das eine Kurve, sonst eine Gerade.

    # Beispiel
    ```julia
    julia> distance_to_drawn_edge(5, 2, 0, 0, 10, 0, 0)
    2.0
    ```
    """
    function distance_to_drawn_edge(px, py, x1, y1, x2, y2, offset)
        offset == 0.0 && return distance_to_edge(px, py, x1, y1, x2, y2)

        cx, cy = curve_control_point(x1, y1, x2, y2, offset)
        best_distance = Inf
        previous_x, previous_y = x1, y1

        # Die Kurve wird für die Klickerkennung in kurze Strecken zerlegt.
        for step in 1:24
            t = step / 24
            current_x, current_y = point_on_curve(x1, y1, cx, cy, x2, y2, t)
            best_distance = min(best_distance,
                                distance_to_edge(px, py, previous_x, previous_y, current_x, current_y))
            previous_x, previous_y = current_x, current_y
        end

        return best_distance
    end

    """
        clicked_edge(state::GameState, x, y)

    Sucht die neutrale Kante, die einem Mausklick am nächsten liegt. Nur diese
    Kante wird anschließend gespielt.

    # Beispiel
    ```julia
    julia> clicked_edge(state, 300, 250)
    Edge(...)
    ```
    """
    function clicked_edge(state::GameState, x, y)
        positions = node_positions(state.graph, width(canvas), height(canvas))
        offsets = parallel_offsets(all_known_edges(state))
        best_edge = nothing
        best_distance = CLICK_DISTANCE

        for edge in valid_moves(state)
            x1, y1 = positions[edge.u.id]
            x2, y2 = positions[edge.v.id]
            distance = distance_to_drawn_edge(x, y, x1, y1, x2, y2, visual_offset(edge, offsets))

            if distance < best_distance
                best_edge = edge
                best_distance = distance
            end
        end

        return best_edge
    end

    """
        rebuild_short_graph!(state::GameState)

    Baut den Teilgraphen der von Short beanspruchten Kanten aus der History neu
    auf. Das ist besonders nach einer Rücknahme wichtig.

    # Beispiel
    ```julia
    julia> rebuild_short_graph!(state)
    ```
    """
    function rebuild_short_graph!(state::GameState)
        # Nach einer Rücknahme ist es am einfachsten und verständlichsten, den
        # Short-Teilgraphen aus der Historie neu aufzubauen.
        vertices = Vertex[state.graph.s, state.graph.t]
        edges = Edge[]

        for (player, edge) in state.history
            player == :short || continue
            push!(edges, edge)
            edge.u in vertices || push!(vertices, edge.u)
            edge.v in vertices || push!(vertices, edge.v)
        end

        state.short_Graph = GameGraph(vertices, edges, state.graph.s, state.graph.t)
    end

    """
        undo_move!(state::GameState)::Bool

    Nimmt genau den letzten Halbzug zurück. Die Funktion setzt den Kantenzustand
    zurück und stellt den richtigen Spieler wieder her.

    # Beispiel
    ```julia
    julia> undo_move!(state)
    true
    ```
    """
    function undo_move!(state::GameState)::Bool
        isempty(state.history) && return false

        player, edge = pop!(state.history)
        state.winner = nothing
        state.current_player = player
        edge.state = :neutral

        if player == :cut
            push!(state.graph.edges, edge)
            sort!(state.graph.edges, by = edge -> edge.id)
        else
            rebuild_short_graph!(state)
        end        
        return true
    end

    """
        undo_for_gui!(state::GameState)::Bool

    Führt die Rücknahme so aus, wie sie in der GUI erwartet wird. Im
    Computer-Modus wird meistens ein ganzer Mensch-Computer-Zugblock
    zurückgenommen.

    # Beispiel
    ```julia
    julia> undo_for_gui!(state)
    true
    ```
    """
    function undo_for_gui!(state::GameState)::Bool
        if !is_computer_game()
            return undo_move!(state)
        end

        isempty(state.history) && return false

        # Wenn der Computer zuletzt geantwortet hat, nehmen wir auch den
        # menschlichen Zug davor zurück. So landet der Mensch wieder am Zug.
        if state.history[end][1] == computer_player()
            undo_move!(state)
            if !isempty(state.history) && state.history[end][1] != computer_player()
                undo_move!(state)
            end
            return true
        end
        return undo_move!(state)
    end

    """
        computer_move!()

    Führt automatisch einen Computerzug aus, falls gerade der Computer am Zug
    ist. Danach wird die GUI neu gezeichnet.

    # Beispiel
    ```julia
    julia> computer_move!()
    ```
    """
    function computer_move!()
        state = current_game_state[]
        (state === nothing || state.winner !== nothing || !is_computer_turn(state)) && return
        if state.current_player == :cut
            t = time_ns()
            edge = weighted_cut(state)
            println("Zugzeit $((time_ns() - t)/1e6) ms")
        else 
            t = time_ns()
            edge = weighted_short(state)
            println("zugzeit $((time_ns() - t)/1e6) ms")
        end 
        edge === nothing && return
        make_move!(state, edge)
        refresh!()
    end

    # -----------------------------------------------------------------------
    # Zeichnen
    # -----------------------------------------------------------------------

    """
        draw_line(ctx, x1, y1, x2, y2)

    Zeichnet eine gerade Linie zwischen zwei Punkten auf dem Cairo-Canvas.

    # Beispiel
    ```julia
    julia> draw_line(ctx, 0, 0, 100, 100)
    ```
    """
    function draw_line(ctx, x1, y1, x2, y2)
        move_to(ctx, x1, y1)
        line_to(ctx, x2, y2)
        stroke(ctx)
    end

    """
        draw_curve(ctx, x1, y1, x2, y2, offset)

    Zeichnet eine Kante. Bei `offset == 0` entsteht eine Gerade, sonst eine
    gekrümmte Linie für parallele Kanten.

    # Beispiel
    ```julia
    julia> draw_curve(ctx, 0, 0, 100, 0, 25)
    ```
    """
    function draw_curve(ctx, x1, y1, x2, y2, offset)
        if offset == 0.0
            draw_line(ctx, x1, y1, x2, y2)
            return
        end

        cx, cy = curve_control_point(x1, y1, x2, y2, offset)

        # Cairo zeichnet kubische Kurven. Diese Kontrollpunkte bilden unsere
        # einfache quadratische Kurve exakt nach.
        c1x = x1 + (2 / 3) * (cx - x1)
        c1y = y1 + (2 / 3) * (cy - y1)
        c2x = x2 + (2 / 3) * (cx - x2)
        c2y = y2 + (2 / 3) * (cy - y2)

        move_to(ctx, x1, y1)
        curve_to(ctx, c1x, c1y, c2x, c2y, x2, y2)
        stroke(ctx)
    end

    """
        draw_edge(ctx, edge::Edge, positions, offsets)

    Zeichnet eine einzelne Kante in der richtigen Farbe. Neutrale Kanten sind
    grau, Short-Kanten blau und Cut-Kanten werden unsichtbar gelassen.

    # Beispiel
    ```julia
    julia> draw_edge(ctx, edge, positions, offsets)
    ```
    """
    function draw_edge(ctx, edge::Edge, positions, offsets)
        # Von Cut gesperrte Kanten sollen im Graphen unsichtbar sein.
        edge.state == :cut && return

        x1, y1 = positions[edge.u.id]
        x2, y2 = positions[edge.v.id]
        offset = visual_offset(edge, offsets)

        if edge.state == :short
            set_source_rgb(ctx, 0.0, 0.25, 1.0)
            set_line_width(ctx, 5.0)
            Cairo.set_dash(ctx, Float64[], 0.0)
        else
            set_source_rgb(ctx, 0.55, 0.55, 0.55)
            set_line_width(ctx, 2.0)
            Cairo.set_dash(ctx, Float64[], 0.0)
        end

        # 1. Kante zeichnen
        draw_curve(ctx, x1, y1, x2, y2, offset)
        Cairo.set_dash(ctx, Float64[], 0.0)

    # ==========================================
    # NEU: Kantengewicht anzeigen
    # ==========================================
    
    # Text-Eigenschaften festlegen
        Cairo.set_font_size(ctx, 13.0)
        Cairo.select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)
    
    # Textfarbe wählen (z. B. Dunkelgrau/Schwarz, damit es lesbar ist)
        Cairo.set_source_rgb(ctx, 0.2, 0.2, 0.2)

    # Gewicht in einen String umwandeln (z.B. "4.5" oder als Int "4", falls glatt)
        weight_str = edge.weight == round(edge.weight) ? string(Int(edge.weight)) : string(edge.weight)

    # Mittelpunkt der Kurve berechnen
    # Da draw_curve vermutlich quadratische Bezier-Kurven nutzt, ist hier eine gute Annäherung 
    # für die Textposition (inklusive des Offsets rechtwinklig zur Linie):
        mx = (x1 + x2) / 2
        my = (y1 + y2) / 2

        if offset != 0
        # Berechne den Normalenvektor für die Verschiebung des Textes bei Kurven
            dx = x2 - x1
            dy = y2 - y1
            len = sqrt(dx^2 + dy^2)
            if len > 0
            # Verschiebe den Text leicht in Richtung des Kurvenbogens (oder entgegengesetzt)
            # 0.5 * offset ist oft ein guter Wert, damit der Text auf/neben der Kurve sitzt
                mx += (-dy / len) * (offset * 0.5)
                my += (dx / len) * (offset * 0.5)
            end
        end

    # Text zentrieren: Ausdehnung des Textes bestimmen
        extents = Cairo.text_extents(ctx, weight_str)
    # extents[1] = x_bearing, extents[2] = y_bearing, extents[3] = width, extents[4] = height
    
    # Textposition so anpassen, dass mx/my exakt die Mitte des Textes ist
    # Wir fügen einen kleinen zusätzlichen Offset hinzu (z. B. -10), damit der Text *über* der Kante schwebt
        text_x = mx - (extents[3] / 2 + extents[1])
        text_y = my - (extents[4] / 2 + extents[2]) - 8 

    # Text auf das Canvas zeichnen
        Cairo.move_to(ctx, text_x, text_y)
        Cairo.show_text(ctx, weight_str)
    end

    """
        draw_vertex(ctx, vertex::Vertex, graph::GameGraph, positions)

    Zeichnet einen Knoten mit Beschriftung. `s` und `t` bekommen eigene Farben,
    damit Start und Ziel sofort erkennbar sind.

    # Beispiel
    ```julia
    julia> draw_vertex(ctx, graph.s, graph, positions)
    ```
    """
    function draw_vertex(ctx, vertex::Vertex, graph::GameGraph, positions)
        x, y = positions[vertex.id]

        if vertex === graph.s
            set_source_rgb(ctx, 0.0, 0.55, 0.15)
        elseif vertex === graph.t
            set_source_rgb(ctx, 0.8, 0.1, 0.1)
        else
            set_source_rgb(ctx, 0.1, 0.35, 0.75)
        end

        arc(ctx, x, y, NODE_RADIUS, 0, 2pi)
        fill(ctx)

        set_source_rgb(ctx, 0.0, 0.0, 0.0)
        set_line_width(ctx, 2.0)
        arc(ctx, x, y, NODE_RADIUS, 0, 2pi)
        stroke(ctx)

        label = vertex === graph.s ? "s" : vertex === graph.t ? "t" : string(vertex.id)
        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        set_font_size(ctx, 14.0)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)

        extents = zeros(Float64, 6)
        ccall((:cairo_text_extents, Cairo.libcairo), Cvoid,
              (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Float64}), ctx.ptr, label, extents)

        move_to(ctx, x - extents[3] / 2, y + extents[4] / 2)
        show_text(ctx, label)
    end

    """
        draw_centered_text(ctx, text::String, x, y, size)

    Zeichnet Text zentriert um den Punkt `(x, y)`. Diese Funktion wird für die
    großen Willkommen- und Game-Over-Texte benutzt.

    # Beispiel
    ```julia
    julia> draw_centered_text(ctx, "GAME OVER", 400, 300, 60)
    ```
    """
    function draw_centered_text(ctx, text::String, x, y, size)
        set_font_size(ctx, size)
        select_font_face(ctx, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_BOLD)

        extents = zeros(Float64, 6)
        ccall((:cairo_text_extents, Cairo.libcairo), Cvoid,
              (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Float64}), ctx.ptr, text, extents)

        move_to(ctx, x - extents[3] / 2, y + extents[4] / 2)
        show_text(ctx, text)
    end

    """
        draw_game_over_overlay(ctx, w, h)

    Zeichnet das dunkle Game-Over-Bild über den Graphen, sobald das Spiel einen
    Gewinner hat. Das Overlay bleibt bis zum neuen Spiel sichtbar.

    # Beispiel
    ```julia
    julia> draw_game_over_overlay(ctx, 800, 600)
    ```
    """
    function draw_game_over_overlay(ctx, w, h)
        state = current_game_state[]
        (state === nothing || state.winner === nothing) && return

        set_source_rgba(ctx, 0.0, 0.0, 0.0, 0.58)
        rectangle(ctx, 0, 0, w, h)
        fill(ctx)

        set_source_rgba(ctx, 1.0, 1.0, 1.0, 1.0)
        draw_centered_text(ctx, "GAME OVER", w / 2, h / 2 - 35, min(w, h) * 0.11)

        set_source_rgba(ctx, 1.0, 0.9, 0.25, 1.0)
        draw_centered_text(ctx, "$(player_name(state.winner)) gewinnt.",
                           w / 2, h / 2 + 40, min(w, h) * 0.06)
    end

    """
        draw_welcome_overlay(ctx, w, h)

    Zeichnet den Startbildschirm, solange noch kein Graph erzeugt wurde.

    # Beispiel
    ```julia
    julia> draw_welcome_overlay(ctx, 800, 600)
    ```
    """
    function draw_welcome_overlay(ctx, w, h)
        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        paint(ctx)

        set_source_rgb(ctx, 0.08, 0.12, 0.18)
        draw_centered_text(ctx, "WILLKOMMEN ZUM SPIEL", w / 2, h / 2 - 30, min(w, h) * 0.085)

        set_source_rgb(ctx, 0.25, 0.35, 0.48)
        draw_centered_text(ctx, "Namen und Spielmodus wählen, dann Neues Spiel starten",
                           w / 2, h / 2 + 45, min(w, h) * 0.03)
    end

    @guarded draw(canvas) do widget
        ctx = getgc(canvas)
        w = width(canvas)
        h = height(canvas)

        set_source_rgb(ctx, 1.0, 1.0, 1.0)
        paint(ctx)

        graph = current_graph[]
        if graph === nothing
            draw_welcome_overlay(ctx, w, h)
            return
        end

        positions = node_positions(graph, w, h)
        state = current_game_state[]
        offsets = state === nothing ? parallel_offsets(graph.edges) : parallel_offsets(all_known_edges(state))

        for edge in graph.edges
            draw_edge(ctx, edge, positions, offsets)
        end

        for vertex in graph.vertices
            draw_vertex(ctx, vertex, graph, positions)
        end

        draw_game_over_overlay(ctx, w, h)
    end

    # -----------------------------------------------------------------------
    # Ereignisse
    # -----------------------------------------------------------------------

    """
        start_new_game!()

    Liest alle Eingaben aus der GUI, erzeugt einen neuen Zufallsgraphen und
    startet einen neuen Spielzustand. Im Computer-Modus zieht der Computer
    sofort, falls er Short spielt.

    # Beispiel
    ```julia
    julia> start_new_game!()
    ```
    """
    function start_new_game!()
        update_name_fields_for_mode!()

        n = tryparse(Int, Gtk4.text(entry_n))
        m = tryparse(Int, Gtk4.text(entry_m))
        short_name = strip(Gtk4.text(entry_short_name))
        cut_name = strip(Gtk4.text(entry_cut_name))

        if n === nothing || m === nothing
            set_status!("Bitte gültige ganze Zahlen für n und m eingeben.")
            return
        end

        if isempty(short_name) || isempty(cut_name)
            set_status!("Bitte Namen für Spieler 1 und Spieler 2/Computer eingeben.")
            return
        end

        graph = random_graph(n, m, weighted = true)
        if graph === nothing
            set_status!("Ungültige Eingabe: n muss > 3 sein, m mindestens n und nicht zu groß.")
            return
        end

        short_player_name[] = short_name
        cut_player_name[] = cut_name
        current_graph[] = graph
        current_game_state[] = new_game(graph)
        refresh!()
        computer_move!()
    end

    signal_connect(btn_new_game, "clicked") do _
        start_new_game!()
    end

    signal_connect(mode_choice, "notify::selected") do args...
        update_name_fields_for_mode!()
        refresh!()
    end

    signal_connect(role_choice, "notify::selected") do args...
        update_name_fields_for_mode!()
        refresh!()
    end

    signal_connect(btn_undo, "clicked") do _
        state = current_game_state[]
        if state === nothing
            set_status!("Es gibt noch kein Spiel.")
        elseif undo_for_gui!(state)
            refresh!()
        else
            set_status!("Es gibt keinen Zug zum Zurücknehmen.")
        end
    end

    gesture = GtkGestureClick()
    push!(canvas, gesture)

    """
        on_canvas_pressed(controller, n_press, x, y)

    Reagiert auf einen Mausklick im Spielfeld. Die Funktion sucht die
    angeklickte Kante, spielt sie und lässt danach gegebenenfalls den Computer
    ziehen.

    # Beispiel
    ```julia
    julia> on_canvas_pressed(controller, 1, 250, 300)
    ```
    """
    function on_canvas_pressed(controller, n_press, x, y)
        state = current_game_state[]
        (state === nothing || state.winner !== nothing || is_computer_turn(state)) && return

        edge = clicked_edge(state, x, y)
        edge === nothing && return

        make_move!(state, edge)
        refresh!()
        computer_move!()
    end

    signal_connect(on_canvas_pressed, gesture, "pressed")

    show(win)
    Gtk4.GLib.start_main_loop()
    Gtk4.GLib.waitforsignal(win, :close_request)
end

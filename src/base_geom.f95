! Types for the most basic geometric objects
module base_geom_mod

    use linked_list_mod
    use math_mod

    implicit none


    type vertex
        ! A vertex in 3-space

        integer :: vert_type ! Whether this is a 1) true vertex or 2) vertex representing an edge midpoint
        real,dimension(3) :: loc ! Location
        real,dimension(3) :: n_g, n_g_mir ! Normal vector associated with this control point
        real :: l_avg ! Average of the edge lengths adjacent to this vertex
        real :: l_min ! Minimum of the edge lengths adjacent to this vertex
        type(list) :: adjacent_vertices ! List of indices for the vertices which share an edge with this vertex
        type(list) :: adjacent_edges ! List of indices for the edges which touch this vertex
        type(list) :: panels ! List of indices for the panels which connect to this vertex
        type(list) :: panels_not_across_wake_edge ! List of indices for the panels which connect to this vertex not across a wake-shedding edge
        integer :: N_wake_edges ! Number of wake edges this vertex belongs to
        integer :: index ! Index of this vertex in the mesh
        integer :: index_in_wake_vertices ! Index of this vertex in the list of wake-shedding vertices
        integer :: top_parent, bot_parent ! Indices of the top and bottom vertices this vertex's strength is determined by (for a wake vertex)
        logical :: on_mirror_plane ! Whether this vertex lies in the mirroring plane
        logical :: clone ! Whether this vertex needs a clone depending on whether it's in a wake-shedding edge
        logical :: mirrored_is_unique ! Whether this vertice's mirror image will be the same for an asymmetric freestream condition
        integer :: i_wake_partner ! Index of the vertex, which along with this one, will determine wake strength
        integer :: N_needed_clones

        contains

            procedure :: init => vertex_init

            ! Initializer-setters
            procedure :: set_whether_on_mirror_plane => vertex_set_whether_on_mirror_plane
            procedure :: set_average_edge_length => vertex_set_average_edge_length
            procedure :: set_needed_clones => vertex_set_needed_clones

            ! Getters
            procedure :: get_needed_clones => vertex_get_needed_clones

    end type vertex


    type vertex_pointer
        ! A pointer to a vertex, for creating vertex arrays

        type(vertex),pointer :: ptr

    end type vertex_pointer


    type edge
        ! A mesh edge

        integer,dimension(2) :: top_verts ! Indices of the end vertices in the mesh vertex array belonging to the top panel
        integer,dimension(2) :: bot_verts ! Indices of the end vertices in the mesh vertex array belonging to the bottom panel
        integer,dimension(2) :: panels ! Indices of the top and bottom (an odd thing to call these) panels for this edge
        integer :: top_midpoint, bot_midpoint
        integer,dimension(2) :: edge_index_for_panel ! Index of the edge which this is for each panel; edge should proceed counterclockwise for the top panel
        logical :: on_mirror_plane ! Whether this edge lies on the mirror plane
        logical :: sheds_wake ! Whether this edge sheds a wake
        real :: l ! Length

        contains

            procedure :: init => edge_init
            procedure :: get_opposing_panel => edge_get_opposing_panel
            procedure :: touches_vertex => edge_touches_vertex
            procedure :: point_top_to_new_vert => edge_point_top_to_new_vert
            procedure :: point_bottom_to_new_vert => edge_point_bottom_to_new_vert

    end type edge
    
contains


    subroutine vertex_init(this, loc, index, vert_type)
        ! Initializes a vertex

        implicit none

        class(vertex),intent(inout) :: this
        real,dimension(3),intent(in) :: loc
        integer,intent(in) :: index, vert_type

        ! Store info
        this%loc = loc
        this%index = index
        this%vert_type = vert_type

        ! Intitialize some data
        this%top_parent = 0
        this%bot_parent = 0

        ! Default cases
        this%mirrored_is_unique = .true.
        this%clone = .false.
        this%N_needed_clones = 0
        this%on_mirror_plane = .false.
        this%i_wake_partner = index
        this%N_wake_edges = 0

    end subroutine vertex_init


    subroutine vertex_set_average_edge_length(this, vertices)
        ! Calculates the average edge length of edges adjacent to this vertex

        implicit none

        class(vertex),intent(inout) :: this
        type(vertex),dimension(:),allocatable,intent(in) :: vertices

        integer :: i, adj_ind, N
        real :: l_i

        ! Loop through adjacent vertices
        this%l_avg = 0.
        this%l_min = huge(this%l_min)
        N = 0
        do i=1,this%adjacent_vertices%len()
            
            ! Get index of adjacent vertex
            call this%adjacent_vertices%get(i, adj_ind)

            ! Calculate edge length
            l_i = dist(this%loc, vertices(adj_ind)%loc)

            ! Get minimum
            this%l_min = min(this%l_min, l_i)

            ! For a vertex on the mirror plane where the adjacent vertex is not on the mirror plane
            ! that length will need to be added twice
            if (this%on_mirror_plane .and. .not. vertices(adj_ind)%on_mirror_plane) then

                ! Add twice
                this%l_avg = this%l_avg + 2*l_i
                N = N + 2
                
            else

                ! Add once
                this%l_avg = this%l_avg + l_i
                N = N + 1

            end if

        end do
        
        ! Compute average
        if (N > 0) then
            this%l_avg = this%l_avg/N
        else
            this%l_avg = 1.
        end if
    
    end subroutine vertex_set_average_edge_length


    subroutine vertex_set_whether_on_mirror_plane(this, mirror_plane)
        ! Sets the member variable telling whether this vertex is on the mirror plane

        implicit none
        
        class(vertex), intent(inout) :: this
        integer, intent(in) :: mirror_plane

        ! Check distance from mirror plane
        if (abs(this%loc(mirror_plane))<1e-12) then

            ! The vertex is on the mirror plane
            this%on_mirror_plane = .true.

        end if
    
        
    end subroutine vertex_set_whether_on_mirror_plane


    subroutine vertex_set_needed_clones(this, mesh_edges)
        ! Determines and sets how many clones this vertex needs

        implicit none
        
        class(vertex),intent(inout) :: this
        type(edge),dimension(:),allocatable,intent(in) :: mesh_edges

        integer :: i, j, i_edge, N_wake_edges_on_mirror_plane

        ! Initialize
        this%N_wake_edges = 0
        this%N_needed_clones = 0
        N_wake_edges_on_mirror_plane = 0

        ! Loop through edges
        do j=1,this%adjacent_edges%len()

            ! Get edge index
            call this%adjacent_edges%get(j, i_edge)

            ! Check if this is a wake-shedding edge
            if (mesh_edges(i_edge)%sheds_wake) then

                ! Update number of wake edges touching this vertex
                this%N_wake_edges = this%N_wake_edges + 1

                ! Check if this edge is on the mirror plane
                if (mesh_edges(i_edge)%on_mirror_plane) then

                    ! Update counter
                    N_wake_edges_on_mirror_plane = N_wake_edges_on_mirror_plane + 1

                    ! If this is a midpoint, then its clone will be unique and it doesn't need any clone
                    if (this%vert_type == 2) then
                        this%mirrored_is_unique = .true.
                    end if

                end if

            end if
        end do

        ! Set number of needed clones for vertices which have at least one wake edge
        if (this%N_wake_edges > 0) then

            ! For regular vertices, this depends on how many wake edges it has
            if (this%vert_type == 1) then

                ! If the vertex is on the mirror plane, then how many clones is dependent upon how many wake edges are on the mirror plane
                if (this%on_mirror_plane) then
                    this%N_needed_clones = this%N_wake_edges - N_wake_edges_on_mirror_plane

                ! If the vertex is not on the mirror plane, then we need one fewer clones than edges
                else
                    this%N_needed_clones = this%N_wake_edges - 1
                end if
            
            ! For midpoints, we will need 1 clone iff it's off the mirror plane
            else
                if (this%on_mirror_plane) then
                    this%N_needed_clones = 0
                else
                    this%N_needed_clones = 1
                end if
            end if
        end if
        
    end subroutine vertex_set_needed_clones


    function vertex_get_needed_clones(this) result(N_clones)
        ! Returns the number of clones this vertex needs

        implicit none
        
        class(vertex),intent(in) :: this

        integer :: N_clones

        N_clones = this%N_needed_clones
        
    end function vertex_get_needed_clones


    subroutine edge_init(this, i1, i2, top_panel, bottom_panel, l)

        implicit none

        class(edge),intent(inout) :: this
        integer,intent(in) :: i1, i2
        integer,intent(in) :: top_panel, bottom_panel
        real,intent(in) :: l

        ! Store indices
        this%top_verts(1) = i1
        this%top_verts(2) = i2

        ! Store panels
        this%panels(1) = top_panel
        this%panels(2) = bottom_panel

        ! Store length
        this%l = l

        ! Set defaults
        this%on_mirror_plane = .false.
        this%sheds_wake = .false.
        this%bot_verts = this%top_verts
    
    end subroutine edge_init


    function edge_get_opposing_panel(this, i_panel) result(i_oppose)
        ! Returns the index of the panel opposite this one on the edge

        implicit none
        
        class(edge),intent(in) :: this
        integer,intent(in) :: i_panel

        integer :: i_oppose

        if (i_panel == this%panels(1)) then
            i_oppose = this%panels(2)
        else if (i_panel == this%panels(2)) then
            i_oppose = this%panels(1)
        else
            i_oppose = 0
        end if
        
    end function edge_get_opposing_panel


    function edge_touches_vertex(this, i_vert) result(touches)
        ! Checks whether the edge touches the given vertex

        implicit none
        
        class(edge),intent(in) :: this
        integer,intent(in) :: i_vert

        logical :: touches

        touches = this%top_verts(1) == i_vert .or. this%top_verts(2) == i_vert
        
    end function edge_touches_vertex


    subroutine edge_point_top_to_new_vert(this, i_orig_vert, i_new_vert)
        ! Overwrites the edge's dependency on i_orig_vert in the top vertices with i_new_vert

        implicit none
        
        class(edge),intent(inout) :: this
        integer,intent(in) :: i_orig_vert, i_new_vert

        if (this%top_verts(1) == i_orig_vert) then
            this%top_verts(1) = i_new_vert
        else if (this%top_verts(2) == i_orig_vert) then
            this%top_verts(2) = i_new_vert
        else if (this%top_midpoint == i_orig_vert) then
            this%top_midpoint = i_new_vert
        end if
        
    end subroutine edge_point_top_to_new_vert


    subroutine edge_point_bottom_to_new_vert(this, i_orig_vert, i_new_vert)
        ! Overwrites the edge's dependency on i_orig_vert in the bottom vertices with i_new_vert

        implicit none
        
        class(edge),intent(inout) :: this
        integer,intent(in) :: i_orig_vert, i_new_vert

        if (this%bot_verts(1) == i_orig_vert) then
            this%bot_verts(1) = i_new_vert
        else if (this%bot_verts(2) == i_orig_vert) then
            this%bot_verts(2) = i_new_vert
        else if (this%bot_midpoint == i_orig_vert) then
            this%bot_midpoint = i_new_vert
        end if
        
    end subroutine edge_point_bottom_to_new_vert

    
end module base_geom_mod
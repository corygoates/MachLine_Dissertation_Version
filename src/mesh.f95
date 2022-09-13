! A basic mesh type consisting of a collection of vertices and panels
module mesh_mod

    use vertex_mod
    use panel_mod

    implicit none

    type mesh

        integer :: N_verts, N_panels = 0
        type(vertex),allocatable,dimension(:) :: vertices
        type(panel),allocatable,dimension(:) :: panels
        logical :: midpoints_created = .false.

        contains

            procedure :: has_zero_area => mesh_has_zero_area
            procedure :: get_indices_to_panel_vertices => mesh_get_indices_to_panel_vertices
            procedure :: allocate_new_vertices => mesh_allocate_new_vertices

    end type mesh

contains


    function mesh_has_zero_area(this, i1, i2, i3) result(has)
        ! Checks whether the panel to be defined by the three given vertices will have zero area

        implicit none

        class(mesh),intent(in) :: this
        integer,intent(in) :: i1, i2, i3
        logical :: has

        ! Check for zero area
        has = norm2(cross(this%vertices(i3)%loc-this%vertices(i2)%loc, this%vertices(i2)%loc-this%vertices(i1)%loc)) < 1.e-12

    end function mesh_has_zero_area


    subroutine mesh_get_indices_to_panel_vertices(this, i_vertices)
        ! Returns of the list of indices which point to the vertices (and midpoints) of each panel

        implicit none

        class(mesh),intent(in) :: this
        integer,dimension(:,:),allocatable,intent(out) :: i_vertices

        integer :: i, j

        ! Allocate space
        allocate(i_vertices(8,this%N_panels))

        ! Get vertex indices for each panel since we will lose this information as soon as this%vertices is reallocated
        do i=1,this%N_panels
            do j=1,this%panels(i)%N

                ! Get vertex indices
                i_vertices(j,i) = this%panels(i)%get_vertex_index(j)
                
                ! Get midpoint indices
                if (this%midpoints_created) then
                    i_vertices(j+this%panels(i)%N,i) = this%panels(i)%get_midpoint_index(j)
                end if

            end do
        end do
        
    end subroutine mesh_get_indices_to_panel_vertices


    subroutine mesh_allocate_new_vertices(this, N_new_verts)
        ! Adds the specified number of vertex objects to the end of the wake mesh's vertex array.
        ! Handles moving panel pointers to the new allocation of previously-existing vertices.

        implicit none

        class(mesh),intent(inout),target :: this
        integer,intent(in) :: N_new_verts
        
        type(vertex),dimension(:),allocatable :: temp_vertices
        integer :: i, j
        integer,dimension(:,:),allocatable :: i_vertices

        ! Get panel vertex indices
        call this%get_indices_to_panel_vertices(i_vertices)

        ! Allocate more space
        allocate(temp_vertices(this%N_verts + N_new_verts))

        ! Copy vertices
        temp_vertices(1:this%N_verts) = this%vertices

        ! Move allocation
        call move_alloc(temp_vertices, this%vertices)

        ! Fix vertex pointers in panel objects (necessary because this%vertices got reallocated)
        do i=1,this%N_panels
            do j=1,this%panels(i)%N

                ! Fix vertex pointers
                this%panels(i)%vertices(j)%ptr => this%vertices(i_vertices(j,i))

                ! Fix midpoint pointers
                if (this%midpoints_created) then
                    this%panels(i)%midpoints(j)%ptr => this%vertices(i_vertices(j+this%panels(i)%N,i))
                end if

            end do
        end do

        ! Update number of vertices
        this%N_verts = this%N_verts + N_new_verts
        
    end subroutine mesh_allocate_new_vertices
    
end module mesh_mod
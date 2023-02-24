! Subroutines for I/O with VTK files
module vtk_mod

    use helpers_mod
    use panel_mod
    use base_geom_mod
    use stl_mod

    implicit none

    type vtk_out

        character(len=:),allocatable :: filename
        integer :: unit
        logical :: cell_data_begun, point_data_begun, cells_subdivided, panels_already_started

        contains

            procedure :: begin => vtk_out_begin
            procedure :: vtk_out_write_points_vertices
            procedure :: vtk_out_write_points_array
            generic :: write_points => vtk_out_write_points_vertices, vtk_out_write_points_array
            procedure :: write_panels => vtk_out_write_panels
            procedure :: write_vertices => vtk_out_write_vertices
            generic :: write_point_scalars => write_point_scalars_real, write_point_scalars_integer
            procedure :: write_point_scalars_real => vtk_out_write_point_scalars_real
            procedure :: write_point_scalars_integer => vtk_out_write_point_scalars_integer
            procedure :: write_cell_header => vtk_out_write_cell_header
            procedure :: write_point_header => vtk_out_write_point_header
            procedure :: write_cell_scalars => vtk_out_write_cell_scalars
            procedure :: write_point_vectors => vtk_out_write_point_vectors
            procedure :: write_cell_vectors => vtk_out_write_cell_vectors
            procedure :: write_cell_normals => vtk_out_write_cell_normals
            procedure :: finish => vtk_out_finish

    end type vtk_out

    
contains


    subroutine vtk_out_begin(this, filename)
        ! Starts writing out a vtk file

        implicit none

        class(vtk_out),intent(inout) :: this
        character(len=:),allocatable,intent(in) :: filename

        logical :: is_open

        ! Store filename
        this%filename = filename

        ! Check if file is opened already
        inquire(file=this%filename, opened=is_open)
        if (is_open) then
            write(*,*) "Cannot write to ", this%filename, ". Already opened."
        end if

        ! Open file
        open(newunit=this%unit, file=this%filename)

        ! Write header
        write(this%unit,'(a)') "# vtk DataFile Version 3.0"
        write(this%unit,'(a)') "MachLine results file. Generated by MachLine, USU AeroLab (c) 2022."
        write(this%unit,'(a)') "ASCII"

        ! Initialize a few checks
        this%cell_data_begun = .false.
        this%point_data_begun = .false.
        this%panels_already_started = .false.
    
    end subroutine vtk_out_begin


    subroutine vtk_out_write_points_vertices(this, vertices, mirror_plane)
        ! Writes out points to the vtk file using the MachLine vertex object

        implicit none

        class(vtk_out),intent(in) :: this
        type(vertex),dimension(:),intent(in) :: vertices
        integer,intent(in),optional :: mirror_plane

        integer :: i, N_verts
        real,dimension(3) :: mirror

        ! Write vertex information
        N_verts = size(vertices)
        write(this%unit,'(a)') "DATASET POLYDATA"
        write(this%unit,'(a i20 a)') "POINTS", N_verts, " float"

        ! Write out vertices
        do i=1,N_verts
            if (present(mirror_plane)) then
                mirror = mirror_across_plane(vertices(i)%loc, mirror_plane)
                write(this%unit,'(e20.12, e20.12, e20.12)') mirror(1), mirror(2), mirror(3)
            else
                write(this%unit,'(e20.12, e20.12, e20.12)') vertices(i)%loc(1), vertices(i)%loc(2), vertices(i)%loc(3)
            end if
        end do
    
    end subroutine vtk_out_write_points_vertices


    subroutine vtk_out_write_points_array(this, vertices, mirror_plane)
        ! Writes out points to the vtk file using a simple array of locations

        implicit none

        class(vtk_out),intent(in) :: this
        real,dimension(:,:),intent(in) :: vertices
        integer,intent(in),optional :: mirror_plane

        integer :: i, N_verts
        real,dimension(3) :: mirror

        ! Write vertex information
        N_verts = size(vertices)/3
        write(this%unit,'(a)') "DATASET POLYDATA"
        write(this%unit,'(a i20 a)') "POINTS", N_verts, " float"

        ! Write out vertices
        do i=1,N_verts
            if (present(mirror_plane)) then
                mirror = mirror_across_plane(vertices(:,i), mirror_plane)
                write(this%unit,'(e20.12, e20.12, e20.12)') mirror(1), mirror(2), mirror(3)
            else
                write(this%unit,'(e20.12, e20.12, e20.12)') vertices(1,i), vertices(2,i), vertices(3,i)
            end if
        end do
    
    end subroutine vtk_out_write_points_array


    subroutine vtk_out_write_panels(this, panels, subdivide, mirror, vertex_index_shift, N_total_panels)
        ! Write out panels to the vtk file; only handles triangular panels

        implicit none

        class(vtk_out),intent(inout) :: this
        type(panel),dimension(:),intent(in) :: panels
        logical,intent(in) :: subdivide, mirror
        integer,intent(in),optional :: vertex_index_shift, N_total_panels

        integer :: i, j, N_panels, shift

        ! Check for shift
        if (present(vertex_index_shift)) then
            shift = vertex_index_shift
        else
            shift = 0
        end if

        ! Determine whether the panels are to be subdivided (for quadratic doublet distributions)
        ! In this case, the edge midpoints will be used to divide each triangular panel into 4 subpanels
        this%cells_subdivided = subdivide

        ! Determine panel info size
        if (present(N_total_panels)) then
            N_panels = N_total_panels
        else
            N_panels = size(panels)
        end if

        ! Write polygon header
        if (.not. this%panels_already_started) then
            this%panels_already_started = .true.
            if (this%cells_subdivided) then
                write(this%unit,'(a i20 i20)') "POLYGONS", N_panels*4, N_panels*16
            else
                write(this%unit,'(a i20 i20)') "POLYGONS", N_panels, N_panels*4
            end if
        end if
        
        ! Write out panels
        do i=1,size(panels)

            ! Write out original panel
            if (.not. this%cells_subdivided) then

                ! Number of vertices
                write(this%unit,'(i1) ',advance='no') 3

                ! Indices of each vertex; remember VTK files use 0-based indexing
                if (mirror) then
                    do j=panels(i)%N,1,-1
                        write(this%unit,'(i20) ',advance='no') panels(i)%get_vertex_index(j) - 1 + shift
                    end do
                else
                    do j=1,panels(i)%N
                        write(this%unit,'(i20) ',advance='no') panels(i)%get_vertex_index(j) - 1 + shift
                    end do
                end if
            
                ! Move to next line
                write(this%unit,*)

            ! Write subpanels
            else

                ! Middle panel
                if (mirror) then
                    write(this%unit,'(i1 i20 i20 i20)') 3, panels(i)%get_midpoint_index(3) - 1 + shift, &
                                                           panels(i)%get_midpoint_index(2) - 1 + shift, &
                                                           panels(i)%get_midpoint_index(1) - 1 + shift
                else
                    write(this%unit,'(i1 i20 i20 i20)') 3, panels(i)%get_midpoint_index(1) - 1 + shift, &
                                                           panels(i)%get_midpoint_index(2) - 1 + shift, &
                                                           panels(i)%get_midpoint_index(3) - 1 + shift
                end if

                ! Corner panels
                do j=1,panels(i)%N
                    if (mirror) then
                        write(this%unit,'(i1 i20 i20 i20)') 3, panels(i)%get_midpoint_index(modulo(j, panels(i)%N)+1) - 1 + shift, &
                                                               panels(i)%get_vertex_index(modulo(j, panels(i)%N)+1) - 1 + shift, &
                                                               panels(i)%get_midpoint_index(j) - 1 + shift
                    else
                        write(this%unit,'(i1 i20 i20 i20)') 3, panels(i)%get_midpoint_index(j) - 1 + shift, &
                                                               panels(i)%get_vertex_index(modulo(j, panels(i)%N)+1) - 1 + shift, &
                                                               panels(i)%get_midpoint_index(modulo(j, panels(i)%N)+1) - 1 + shift
                    end if
                end do
            end if

        end do
    
    end subroutine vtk_out_write_panels


    subroutine vtk_out_write_vertices(this, N_verts)
        ! Writes vertices (VTK vertices, which are different than points) to the file using default mapping (the first vertex is 1, etc.)

        implicit none

        class(vtk_out),intent(in) :: this
        integer,intent(in) :: N_verts

        integer :: i

        ! Write out vertices
        write(this%unit,'(a i20 i20)') "VERTICES", N_verts, N_verts*2
        do i=1,N_verts

            ! Index of each vertex
            write(this%unit,'(i1 i20)') 1, i-1

        end do
    
    end subroutine vtk_out_write_vertices


    subroutine vtk_out_write_point_header(this, N_points)
        ! Checks whether the point data header has been written and writes it if necessary

        class(vtk_out), intent(inout) :: this
        integer, intent(in) :: N_points

        if (.not. this%point_data_begun) then
            
            ! Write out header
            write(this%unit,'(a i20)') "POINT_DATA", N_points

            ! Set toggle that header has already been written
            this%point_data_begun = .true.

        end if
        
    end subroutine vtk_out_write_point_header


    subroutine vtk_out_write_cell_header(this, N_cells)
        ! Checks whether the cell data header has been written and writes it if necessary

        class(vtk_out), intent(inout) :: this
        integer, intent(in) :: N_cells

        if (.not. this%cell_data_begun) then
            
            ! Write out header
            if (this%cells_subdivided) then
                write(this%unit,'(a i20)') "CELL_DATA", N_cells*4
            else
                write(this%unit,'(a i20)') "CELL_DATA", N_cells
            end if

            ! Set toggle that header has already been written
            this%cell_data_begun = .true.

        end if
        
    end subroutine vtk_out_write_cell_header


    subroutine vtk_out_write_cell_scalars(this, data, label, same_over_subpanels)
        ! Writes out cell scalar data

        implicit none

        class(vtk_out),intent(inout) :: this
        real,dimension(:),intent(in) :: data
        character(len=*),intent(in) :: label
        logical,intent(in) :: same_over_subpanels

        integer :: N_cells, i, j, N, N_cycle

        ! Figure out size of dataset
        if (this%cells_subdivided) then
            if (same_over_subpanels) then
                N_cells = size(data)*4
                N_cycle = 1
                N = N_cells/4
            else
                N_cells = size(data)
                N_cycle = 4
                N = N_cells/4
            end if
        else
            N_cells = size(data)
            N_cycle = 1
            N = N_cells
        end if

        ! Write header
        call this%write_cell_header(N_cells)

        ! Write data
        write(this%unit,'(a, a, a)') "SCALARS ", label, " float 1"
        write(this%unit,'(a)') "LOOKUP_TABLE default"
        do i=1,N

            ! Original
            write(this%unit, '(e20.12)') data((i-1)*N_cycle+1)

            ! Subpanels
            if (this%cells_subdivided) then
                if (same_over_subpanels) then
                    do j=1,3
                        write(this%unit,'(e20.12)') data(i)
                    end do
                else
                    do j=1,3
                        write(this%unit,'(e20.12)') data((i-1)*N_cycle+1+j)
                    end do
                end if
            end if
        end do
    
    end subroutine vtk_out_write_cell_scalars


    subroutine vtk_out_write_cell_vectors(this, data, label, same_over_subpanels)
        ! Writes out cell vector data

        implicit none

        class(vtk_out),intent(inout) :: this
        real,dimension(:,:),intent(in) :: data
        character(len=*),intent(in) :: label
        logical,intent(in) :: same_over_subpanels

        integer :: N_cells, i, j, N_cycle, N

        ! Number of cells and subdivisions
        if (this%cells_subdivided) then
            if (same_over_subpanels) then
                N_cells = 4*size(data)/3
                N_cycle = 1
                N = N_cells/4
            else
                N_cells = size(data)/3
                N_cycle = 4
                N = N_cells/4
            end if
        else
            N_cells = size(data)/3
            N_cycle = 1
            N = N_cells
        end if

        ! Write cell data header
        call this%write_cell_header(N_cells)

        ! Write header
        write(this%unit,'(a, a, a)') "VECTORS ", label, " float"

        ! Loop through cells
        do i=1,N

            ! Original
            write(this%unit,'(e20.12, e20.12, e20.12)') data(1,(i-1)*N_cycle+1), data(2,(i-1)*N_cycle+1), data(3,(i-1)*N_cycle+1)

            ! Subpanels
            if (this%cells_subdivided) then
                if (same_over_subpanels) then
                    do j=1,3
                        write(this%unit,'(e20.12, e20.12, e20.12)') data(1,i), &
                                                                    data(2,i), &
                                                                    data(3,i)
                    end do
                else
                    do j=1,3
                        write(this%unit,'(e20.12, e20.12, e20.12)') data(1,(i-1)*N_cycle+1+j), &
                                                                    data(2,(i-1)*N_cycle+1+j), &
                                                                    data(3,(i-1)*N_cycle+1+j)
                    end do
                end if
            end if
        end do
    
    end subroutine vtk_out_write_cell_vectors


    subroutine vtk_out_write_cell_normals(this, panels, mirror_plane)
        ! Writes out cell normals

        implicit none

        class(vtk_out),intent(inout) :: this
        type(panel),dimension(:),intent(in) :: panels
        integer,intent(in),optional :: mirror_plane

        integer :: N_cells, i, j
        real,dimension(3) :: mirror

        ! Write cell data header
        N_cells = size(panels)
        call this%write_cell_header(N_cells)

        ! Write vectors
        write(this%unit,'(a)') "NORMALS normals float"
        do i=1,N_cells

            ! Mirror
            if (present(mirror_plane)) then
                mirror = mirror_across_plane(panels(i)%n_g, mirror_plane)
                write(this%unit,'(e20.12, e20.12, e20.12)') mirror(1), mirror(2), mirror(3)

                ! Same normal for subpanels
                if (this%cells_subdivided) then
                    do j=1,3
                        write(this%unit,'(e20.12, e20.12, e20.12)') mirror(1), mirror(2), mirror(3)
                    end do
                end if

            ! Original
            else
                write(this%unit,'(e20.12, e20.12, e20.12)') panels(i)%n_g(1), panels(i)%n_g(2), panels(i)%n_g(3)

                ! Same normal for subpanels
                if (this%cells_subdivided) then
                    do j=1,3
                        write(this%unit,'(e20.12, e20.12, e20.12)') panels(i)%n_g(1), panels(i)%n_g(2), panels(i)%n_g(3)
                    end do
                end if
            end if
        end do
    
    end subroutine vtk_out_write_cell_normals


    subroutine vtk_out_write_point_scalars_real(this, data, label)
        ! Writes out point scalar data

        implicit none

        class(vtk_out),intent(inout) :: this
        real,dimension(:),intent(in) :: data
        character(len=*),intent(in) :: label

        integer :: i, N_points

        ! Write point data header
        N_points = size(data)
        call this%write_point_header(N_points)

        ! Write data
        write(this%unit,'(a, a, a)') "SCALARS ", label, " float 1"
        write(this%unit,'(a)') "LOOKUP_TABLE default"
        do i=1,N_points
            write(this%unit,'(e20.12)') data(i)
        end do
    
    end subroutine vtk_out_write_point_scalars_real


    subroutine vtk_out_write_point_scalars_integer(this, data, label)
        ! Writes out point scalar data

        implicit none

        class(vtk_out),intent(inout) :: this
        integer,dimension(:),intent(in) :: data
        character(len=*),intent(in) :: label

        integer :: i, N_points

        ! Write point data header
        N_points = size(data)
        call this%write_point_header(N_points)

        ! Write data
        write(this%unit,'(a, a, a)') "SCALARS ", label, " int 1"
        write(this%unit,'(a)') "LOOKUP_TABLE default"
        do i=1,N_points
            write(this%unit,'(i12)') data(i)
        end do
    
    end subroutine vtk_out_write_point_scalars_integer


    subroutine vtk_out_write_point_vectors(this, data, label)
        ! Writes out point vector data

        implicit none

        class(vtk_out),intent(inout) :: this
        real,dimension(:,:),intent(in) :: data
        character(len=*),intent(in) :: label

        integer :: N_points, i

        ! Write cell data header
        N_points = size(data)/3
        call this%write_point_header(N_points)

        ! Write vectors
        write(this%unit,'(a, a, a)') "VECTORS ", label, " float"
        do i=1,N_points
            write(this%unit,'(e20.12, e20.12, e20.12)') data(1,i), data(2,i), data(3,i)
        end do
    
    end subroutine vtk_out_write_point_vectors
    

    subroutine vtk_out_finish(this)
        ! Closes the file

        implicit none

        class(vtk_out),intent(in) :: this

        ! Close the file
        close(this%unit)
    
    end subroutine vtk_out_finish


    subroutine load_surface_vtk(mesh_file, N_verts, N_panels, vertices, panels)
        ! Loads a surface mesh from a vtk file. Only a body.

        implicit none

        character(len=:),allocatable,intent(in) :: mesh_file
        integer,intent(out) :: N_verts, N_panels
        type(vertex),dimension(:),allocatable,intent(out) :: vertices
        type(panel),dimension(:),allocatable,intent(out) :: panels

        character(len=200) :: dummy_read
        real,dimension(:,:),allocatable :: vertex_locs
        integer :: i, N, i1, i2, i3, N_duplicates,unit
        integer,dimension(:),allocatable :: new_ind

        ! Open file
        open(newunit=unit, file=mesh_file)

            ! Determine number of vertices
            read(unit,*) ! Header
            read(unit,*) ! Header
            read(unit,*) ! Header
            read(unit,*) ! Header
            read(unit,*) dummy_read, N_verts, dummy_read

            ! Store vertices
            allocate(vertex_locs(3,N_verts))
            do i=1,N_verts

                ! Read in from file
                read(unit,*) vertex_locs(1,i), vertex_locs(2,i), vertex_locs(3,i)

            end do

            ! Find duplicates
            call collapse_duplicate_vertices(vertex_locs, vertices, N_verts, N_duplicates, new_ind)

            ! Determine number of panels
            read(unit,*) dummy_read, N_panels, dummy_read

            ! Allocate panel array
            allocate(panels(N_panels))

            ! Initialize panels
            do i=1,N_panels

                ! Get vertex indices
                read(unit,'(a)') dummy_read
                
                ! Check its a triangular panel
                if (dummy_read(1:2) == '3 ') then
                    read(dummy_read,*) N, i1, i2, i3
                else
                    write(*,*) "!!! MachLine supports only triangular panels."
                    stop
                end if

                ! Initialize; need +1 because VTK uses 0-based indexing
                call panels(i)%init(vertices(new_ind(i1+1)), vertices(new_ind(i2+1)), vertices(new_ind(i3+1)), i)

            end do

        close(1)
    
    end subroutine load_surface_vtk

    
end module vtk_mod
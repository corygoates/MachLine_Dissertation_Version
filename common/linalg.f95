! Linear algebra subroutines
module linalg_mod

    use math_mod

    implicit none
    
contains


subroutine matinv(n, a, ai)
      ! This sobroutine inverts a matrix "a" and returns the inverse in "ai"
      ! n  - Input by user, an integer specifying the size of the matrix to be inverted.
      ! a  - Input by user, an n by n real array containing the matrix to be inverted.
      ! ai - Returned by subroutine, an n by n real array containing the inverted matrix.
      ! d  - Work array, an n by 2n real array used by the subroutine.
      ! io - Work array, a 1-dimensional integer array of length n used by the subroutine.
      ! THIS FUNCTION SHOULD NEVER BE callED! NEVER INVERT A MARTIX EXPLICITLY!
      ! Unless you know what you're doing. Odds are you may not, so be careful.

      implicit none

      integer :: n,i,j,k,m,itmp
      real :: a(n,n),ai(n,n),tmp,r
      real,allocatable,dimension(:,:) :: d
      integer,allocatable,dimension(:) :: io

      allocate(d(n,2*n))
      allocate(io(n))

      d(:,:) = 0.0
      io(:) = 0

!     Fill in the "io" and "d" matrix.
!     ********************************
      do i=1,n
         io(i)=i
      end do
      do i=1,n
         do j=1,n
            d(i,j)=a(i,j)
            if(i.eq.j)then
               d(i,n+j)=1.
            else
               d(i,n+j)=0.
            endif
         end do
      end do

!     Scaling
!     *******
      do i=1,n
         m=1
         do k=2,n
            if(abs(d(i,k)).gt.abs(d(i,m))) m=k
         end do
         tmp=d(i,m)
         do k=1,2*n
            d(i,k)=d(i,k)/tmp
         end do
      end do

!     Lower Elimination
!     *****************
      do i=1,n-1
!        Pivoting
!        ********
         m=i
         do j=i+1,n
            if(abs(d(io(j),i)).gt.abs(d(io(m),i))) m=j
         end do
         itmp=io(m)
         io(m)=io(i)
         io(i)=itmp
!        Scale the Pivot element to unity
!        ********************************
         r=d(io(i),i)
         do k=1,2*n
            d(io(i),k)=d(io(i),k)/r
         end do
!        ********************************
         do j=i+1,n
            r=d(io(j),i)
            do k=1,2*n
               d(io(j),k)=d(io(j),k)-r*d(io(i),k)
            end do
         end do
      end do

!     Upper Elimination
!     *****************
      r=d(io(n),n)
      do k=1,2*n
         d(io(n),k)=d(io(n),k)/r
      end do
      do i=n-1,1,-1
         do j=i+1,n
            r=d(io(i),j)
            do k=1,2*n
               d(io(i),k)=d(io(i),k)-r*d(io(j),k)
            end do
         end do
      end do

!     Fill Out "ai" matrix
      do i=1,n
         do j=1,n
            ai(i,j)=d(io(i),n+j)
         end do
      end do

      ! Cleanup
      deallocate(d)
      deallocate(io)

end subroutine matinv


function matmul_lu(n, A, x) result(b)
  ! Gives the matrix product [L][U]x = b where A = [L\U] (Doolittle LU decomposition)
  ! NOT TESTED

  implicit none

  integer,intent(in) :: n
  real,dimension(n,n),intent(in) :: A
  real,dimension(n),intent(in) :: x

  real,dimension(n) :: b, d
  integer :: i, j

  d = 0.

  ! [U]x = d
  do i=1,n
    do j=i,n
      d(i) = d(i) + A(i,j)*x(j)
    end do
  end do

  ! [L]x = b
  do i=1,n
    do j=1,i-1
      b(i) = b(i) + A(i,j)*d(j)
    end do
    b(i) = b(i) + d(i) ! L(i,i) = 1.
  end do

end function matmul_lu


subroutine lu_solve(n, A, b, x)
  ! Solves a general [A]x=b on an nxn matrix
  ! This replaces A (in place) with its LU decomposition (permuted row-wise)

    implicit none

    integer,intent(in) :: n
    real,dimension(n),intent(in) :: b
    real,dimension(:),allocatable,intent(out) :: x
    real,dimension(n,n),intent(inout) :: A

    integer,allocatable,dimension(:) :: indx
    integer :: D, info

    allocate(indx(n))

    ! Compute decomposition
    call lu_decomp(A, n, indx, D, info)

    ! if the matrix is nonsingular, then backsolve to find X
    if (info == 1) then
        write(*,*) 'Subroutine lu_solve() failed. The given matrix is singular (i.e. no unique solution). Quitting...'
        stop
    else
        call lu_back_sub(A, n, indx, b, x)
    end if

    ! Cleanup
    deallocate(indx)

end subroutine lu_solve


!*******************************************************
!*    LU decomposition routines used by test_lu.f90    *
!*                                                     *
!*                 F90 version by J-P Moreau, Paris    *
!*    improved for F95 by Cory Goates, Logan, UT, USA  *
!* --------------------------------------------------- *
!* Reference:                                          *
!*                                                     *
!* "Numerical Recipes By W.H. Press, B. P. Flannery,   *
!*  S.A. Teukolsky and W.T. Vetterling, Cambridge      *
!*  University Press, 1986" [BIBLI 08].                *
!*                                                     *
!*******************************************************


subroutine lu_decomp(A, N, indx, D, code)
  ! Given an N x N matrix A, this routine replaces it by the LU
  ! decomposition of a rowwise permutation of itself. A and N  
  ! are input. indx is an output vector which records the row  
  ! permutation effected by the partial pivoting; D is output  
  ! as -1 or 1, depending on whether the number of row inter-  
  ! changes was even or odd, respectively. This routine is used
  ! in combination with LUBKSB to solve linear equations or to 
  ! invert a matrix. Return code is 1 if matrix is singular.  

  implicit none


  real,dimension(N,N),intent(inout) :: A
  integer,intent(in) :: N
  integer,dimension(N),intent(out) :: indx
  integer,intent(out) :: code, D

  real,dimension(N) :: VV
  real,parameter :: tiny=1.5e-20
  integer :: i, j, k, imax
  real :: amax, dum, sum

  ! Initialize
  D = 1
  code = 0
  imax = 0

  ! Loop over rows to get implicit scaling information
  do i=1,N

    ! Get largest element in this row
    amax=0.0
    do j=1,N
      if (abs(A(i,j)) > amax) then
        amax = abs(A(i,j))
      end if
    end do

    ! Check the largest element in this row is nonzero
    if (amax <= tiny) then
      code = 1 ! Singular matrix
      return
    end if

    ! Store implicit scaling
    vv(i) = 1.0 / amax

  end do

  ! Loop over columns of Crout's method
  do j=1,N
    do i=1,J-1
      sum = A(i,j)
      do k=1,i-1
        sum = sum - A(i,k)*A(k,j)
      end do
      A(i,j) = sum
    end do

    ! Initialize search for largest pivot element
    amax = 0.0
    do i=j,N

      sum = A(i,j)
      do k=1,j-1
        sum = sum - A(i,k)*A(k,j)
      end do
      A(i,j) = sum

      ! Determine figure of merit for the pivot
      dum = vv(i)*abs(sum)
      if (dum >= amax) then
        imax = i
        amax = dum
      end if

    end do

    ! Figure out if we need to interchange rows
    if (j /= imax) then

      ! Perform interchange
      do k=1,N
        dum = A(imax,k)
        A(imax,k) = A(j,k)
        A(j,k) = dum
      end do

      ! Update the sign of D since a row interchange has occurred
      D = -D

      ! Interchange the implicit scaling factor
      vv(imax) = vv(j)

    end if

    ! Store pivoting
    indx(j) = imax

    ! Replace zero pivot element with small parameter
    if (abs(A(j,j)) < tiny) then
      A(j,j) = tiny
    end if

    ! Divide by pivot element
    if (j /= N) then
      dum = 1.0 / A(j,j)
      do i=j+1,N
        A(i,j) = A(i,j)*dum
      end do
    end if

  end do

end subroutine lu_decomp


subroutine lu_back_sub(A, N, indx, b, x)
  ! Solves the set of N linear equations Ax = b.  Here A is     
  ! input, not as the matrix A but rather as its LU decomposition, 
  ! determined by the routine LUDCMP. indx is input as the permuta-
  ! tion vector returned by LUDCMP. b is input as the right-hand   
  ! side vector b. The solution vector is x. A, N, b and
  ! indx are not modified by this routine and can be used for suc- 
  ! cessive calls with different right-hand sides. This routine is 
  ! also efficient for plain matrix inversion.                     

  implicit none

  integer,intent(in) :: N
  real,dimension(N,N),intent(in) :: A
  real,dimension(N),intent(in) :: b
  integer,dimension(N),intent(in) :: indx
  real,dimension(:),allocatable,intent(out) :: x

  real :: sum
  integer :: ii,i,j,ll

  ! Initialize solution
  allocate(x, source=b)

  ! Set tracker to ignore leading zeros in b
  ii = 0

  ! Forward substitution
  do i=1,N

    ! Untangle pivoting
    ll = indx(i)
    sum = x(ll)
    x(ll) = x(i)

    ! If a nonzero element of b has already been encountered
    if (ii /= 0) then
      do J=ii,i-1
        sum = sum - A(i,J)*x(J)
      end do

    ! Check for first nonzero element of b
    else if(sum /= 0.0) then
      ii = i
    end if

    x(i) = sum

  end do

  ! Back substitution
  do i=N,1,-1
    sum = x(i)
    do j=i+1,N
      sum = sum - A(i,j)*x(j)
    end do
    x(i) = sum / A(i,i)
  end do

end subroutine lu_back_sub


subroutine snyder_lu_decomp(a,n)
  ! Computes the LU decomposition for a diagonally dominant matrix (no pivoting is done).           
  !   Inputs:  n = number of equations/unknowns                 
  !            a = nxn coefficient matrix                       
  !   Outputs: a = nxn matrix containing the LU matrices        
  !                                                             
  ! Deryl Snyder, 10-16-98                                      
  implicit none
  integer :: n,i,j,k
  real a(n,n),z

  do k=1,n-1
    do i=k+1,n
      z=a(i,k)/a(k,k)                     !compute gauss factor
      a(i,k)=z                            !store gauss factor in matrix
      do j=k+1,n
        a(i,j)=a(i,j)-z*a(k,j)            !apply row operation
      end do
    end do
  end do
end subroutine snyder_lu_decomp


subroutine snyder_lu_solve(a,b,x,n)
  ! Solves for the unknowns (x) given the LU matrix and the right hand side.                                    C
  !   Inputs:  n = number of equations/unknowns                        
  !            a = nxn matrix containing the L and U values           
  !            b = n vector containing right hand side values          
  !   Outputs: x = n vector containing solution                        
  !                                                                    
  ! Deryl Snyder, 10-16-98                                             

  implicit none

  integer :: n,i,j,k
  real a(n,n),b(n),x(n)

  do i=1,n
     x(i)=b(i)
  end do

  ! Forward substitution
  do k=1,n-1
    do i=k+1,n
      x(i)=x(i)-a(i,k)*x(k)
    enddo
  enddo

  ! Back substitution
  do i=n,1,-1
    do j=i+1,n
      x(i)=x(i)-a(i,j)*x(j)
    end do
    x(i)=x(i)/a(i,i)
  end do

end subroutine snyder_lu_solve


subroutine quadratic_fit(pts, a, b, c)
  ! Fits a parabola through three specified   
  ! points and returns the coefficients a, b, c defining this parabola 
  ! according to the equation y = a * x**2 + b * x + c                 
  !            pts = list of three (x, y) points                       
  !   Outputs: a, b, c = quadratic coefficients                        

  implicit none

  real,dimension(3, 2),intent(in) :: pts
  real,intent(out) :: a, b, c

  integer :: i
  real,dimension(3,3) :: m
  real,dimension(:),allocatable :: coeff

  do i = 1, 3
    m(i, 1) = pts(i, 1)**2
    m(i, 2) = pts(i, 1)
    m(i, 3) = 1.0
  end do

  call lu_solve(3, m, pts(:,2), coeff)

  a = coeff(1)
  b = coeff(2)
  c = coeff(3)

end subroutine quadratic_fit

    
end module linalg_mod
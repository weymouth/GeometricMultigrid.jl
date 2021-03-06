mg!(st::SolveState;kw...) = iterate!(st,Vcycle!;mxiter=32,kw...)
function mg(A::AbstractMatrix,b::AbstractVector;kw...) 
    x=zero(b)
    return x,mg!(mg_state(A,x,b);kw...)
end
mg_state(A,x,b) = fill_children!(SolveState(A,x,residual(A,x,b)))

@inline Vcycle!(st::SolveState;kw...) = Vcycle!(st,st.child;kw...)
@inline Vcycle!(fine::SolveState,coarse::Nothing;kw...) = GS!(fine;kw...)
function Vcycle!(fine::SolveState,coarse::SolveState;
                 precond!::Function=(st;kw...)->GS!(st,inner=0),smooth!::Function=GS!,kw...)
    # set up & solve coarse recursively
    precond!(fine;kw...)
    restrict!(coarse.r,fine.r)
    fill!(coarse.x,0.)
    Vcycle!(coarse;precond!,smooth!,kw...)
    # correct & solve fine
    prolongate!(fine.ϵ,coarse.x)
    increment!(fine)
    smooth!(fine;kw...)
end

restrict!(a,b) = @loop a[I] = sum(@inbounds(b[J]) for J ∈ up(I))
prolongate!(a,b) = @loop a[I] = b[down(I)]

@inline up(I::CartesianIndex{N},a=0) where N = (2I-2oneunit(I)):(2I-oneunit(I)-δ(a,N))
@inline down(I) = CartesianIndex((I+2oneunit(I)).I .÷2)

function fill_children!(st::SolveState)
    if isdivisible(st) && isnothing(st.child)
        st.child = create_child(st.A.L,eltype(st.x))
        fill_children!(st.child)
    end
    return st
end

function create_child(b::AbstractArray{T,N},xT::Type) where {T,N}
    dims = 1 .+ Base.front(size(b)) .÷ 2
    a = zeros(T,dims...,N-1)
    x = FieldVector(zeros(xT,dims))
    for i ∈ 1:N-1, I ∈ x.R
        a[I,i] = 0.5sum(@inbounds(b[J,i]) for J ∈ up(I,i))
    end
    SolveState(Poisson(a),x,zero(x))
end

@inline isdivisible(N::Int) = mod(N,2)==0 && N>2
@inline isdivisible(st::SolveState) = all(size(st.x.R) .|> isdivisible)

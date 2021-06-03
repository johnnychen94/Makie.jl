argtypes(x::Combined{T, A}) where {T, A} = A
argtypes(x) = Any

function data_limits(x)
    error("No datalimits for $(typeof(x)) and $(argtypes(x))")
end

function data_limits(x::Atomic)
    isempty(x.plots) ? atomic_limits(x) : data_limits(x.plots)
end

"""
Data limits calculate a minimal boundingbox from the data points in a plot.
This doesn't include any transformations, markers etc.
"""
function atomic_limits(x::Atomic{<: Tuple{Arg1}}) where Arg1
    return xyz_boundingbox(identity, to_value(x[1]))
end

function atomic_limits(x::Atomic{<: Tuple{X, Y, Z}}) where {X, Y, Z}
    return xyz_boundingbox(identity, to_value.(x[1:3])...)
end

function atomic_limits(x::Atomic{<: Tuple{X, Y}}) where {X, Y}
    return xyz_boundingbox(identity, to_value.(x[1:2])...)
end

_isfinite(x) = isfinite(x)
_isfinite(x::VecTypes) = all(isfinite, x)
scalarmax(x::Union{Tuple, AbstractArray}, y::Union{Tuple, AbstractArray}) = max.(x, y)
scalarmax(x, y) = max(x, y)
scalarmin(x::Union{Tuple, AbstractArray}, y::Union{Tuple, AbstractArray}) = min.(x, y)
scalarmin(x, y) = min(x, y)

extrema_nan(itr::Pair) = (itr[1], itr[2])
extrema_nan(itr::ClosedInterval) = (minimum(itr), maximum(itr))

function extrema_nan(itr)
    vs = iterate(itr)
    vs === nothing && return (NaN, NaN)
    v, s = vs
    vmin = vmax = v
    # find first finite value
    while vs !== nothing && !_isfinite(v)
        v, s = vs
        vmin = vmax = v
        vs = iterate(itr, s)
    end
    while vs !== nothing
        x, s = vs
        vs = iterate(itr, s)
        _isfinite(x) || continue
        vmax = scalarmax(x, vmax)
        vmin = scalarmin(x, vmin)
    end
    return (vmin, vmax)
end

function xyz_boundingbox(transform_func, mesh::GeometryBasics.Mesh)
    xyz_boundingbox(transform_func, decompose(Point, mesh))
end

function xyz_boundingbox(transform_func, xyz)
    isempty(xyz) && return FRect3D()
    mini, maxi = extrema_nan((apply_transform(transform_func, point) for point in xyz))
    w = maxi .- mini
    return FRect3D(to_ndim(Vec3f0, mini, 0), to_ndim(Vec3f0, w, 0))
end

const NumOrArray = Union{AbstractArray, Number}

function xyz_boundingbox(transform_func, x::AbstractVector, y::AbstractVector, z::NumOrArray=0)
    # use lazy variant of broadcast!
    points = Base.broadcasted(Point3, x, y', z)
    return xyz_boundingbox(transform_func, points)
end

function xyz_boundingbox(transform_func, x::NumOrArray, y::NumOrArray, z::NumOrArray = 0)
    # use lazy variant of broadcast!
    points = Base.broadcasted(Point3, x, y, z)
    return xyz_boundingbox(transform_func, points)
end

function xyz_boundingbox(transform_func, x, y, z = 0)
    isempty(x) && return FRect3D()
    minmax = extrema_nan.(apply_transform.((transform_func,), (x, y, z)))
    mini, maxi = Vec(first.(minmax)), Vec(last.(minmax))
    w = maxi .- mini
    return FRect3D(to_ndim(Vec3f0, mini, 0), to_ndim(Vec3f0, w, 0))
end

const ImageLike{Arg} = Union{Heatmap{Arg}, Image{Arg}}
function data_limits(x::ImageLike{<: Tuple{X, Y, Z}}) where {X, Y, Z}
    xyz_boundingbox(identity, to_value.((x[1], x[2]))...)
end

function data_limits(x::Volume)
    _to_interval(r) = ((lo, hi) = extrema(r); lo..hi)
    axes = (x[1], x[2], x[3])
    xyz_boundingbox(identity, _to_interval.(to_value.(axes))...)
end

function text_limits(x::VecTypes)
    p = to_ndim(Vec3f0, x, 0.0)
    return FRect3D(p, p)
end

function text_limits(x::AbstractVector)
    return FRect3D(x)
end

FRect3D_from_point(p::VecTypes{2}) = FRect3D(Point3f0(p..., 0), Point3f0(0, 0, 0))
FRect3D_from_point(p::VecTypes{3}) = FRect3D(Point3f0(p...), Point3f0(0, 0, 0))


function atomic_limits(x::Text{<:Tuple{<:GlyphLayout3}})
    if x.space[] == :data
        boundingbox(x)
    elseif x.space == :screen
        FRect3D_from_point(x.position[])
    else
        error()
    end
end

function atomic_limits(x::Text{<:Tuple{<:AbstractArray{<:GlyphLayout3}}})
    if x.space[] == :data
        boundingbox(x)
    elseif x.space == :screen
        bb = FRect3D_from_point(x.position[][1])
        for p in x.position[][2:end]
            bb = union(bb, FRect3D_from_point(p))
        end
        bb
    else
        error()
    end
end

# function atomic_limits(x::Text{<: Tuple{Arg1}}) where Arg1
#     if x.space[] == :data
#         return boundingbox(x)
#     elseif x.space[] == :screen
#         if x[1][] isa AbstractArray
#             bb = FRect3D_from_point(x.position[][1])
#             for p in x.position[][2:end]
#                 bb = union(bb, FRect3D_from_point(p))
#             end
#         else
#             if x.position[] isa Union{StaticArrays.StaticArray, Tuple{Real, Real}, GeometryBasics.Point}
#                 bb = FRect3D_from_point(x.position[])
#             else
#                 bb = FRect3D_from_point(x.position[][1])
#                 for p in x.position[][2:end]
#                     bb = union(bb, FRect3D_from_point(p))
#                 end
#                 bb
#             end
#         end
#         bb
#     end
# end

# function data_limits(x::Annotations)
#     # data limits is supposed to not include any transformation.
#     # for the annotation, we use the model matrix directly, so we need to
#     # to inverse that transformation for the correct limits
#     bb = data_limits(x.plots[1])
#     return inv(modelmatrix(x)) * bb
# end

isfinite_rect(x::Rect) = all(isfinite.(minimum(x))) &&  all(isfinite.(maximum(x)))

function data_limits(plots::Vector)
    isempty(plots) && return
    bb = FRect3D()
    plot_idx = iterate(plots)
    while plot_idx !== nothing
        plot, idx = plot_idx
        plot_idx = iterate(plots, idx)
        # axis shouldn't be part of the data limit
        isaxis(plot) && continue
        bb2 = data_limits(plot)::FRect3D
        isfinite_rect(bb) || (bb = bb2)
        isfinite_rect(bb2) || continue
        bb = union(bb, bb2)
    end
    bb
end

data_limits(s::Scene) = data_limits(plots_from_camera(s))
data_limits(s::Figure) = data_limits(s.scene)
data_limits(s::FigureAxisPlot) = data_limits(s.figure)
data_limits(plot::Combined) = data_limits(plot.plots)

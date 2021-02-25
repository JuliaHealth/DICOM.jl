struct DICOMData
    meta::Dict{Tuple{UInt16,UInt16},Any}
    endian::Symbol
    isexplicit::Bool
    vr::Dict{Tuple{UInt16,UInt16},String}
end

function Base.getproperty(dcm::DICOMData, sym::Symbol)
    if sym ∈ fieldnames(DICOMData)
        return getfield(dcm, sym)
    else
        return lookup(dcm, sym)
    end
end

Base.setproperty!(dcm::DICOMData, sym::Symbol, val) = setindex!(dcm, val, sym)

function Base.propertynames(dcm::DICOMData)
    basic_properties = invoke(propertynames, Tuple{Any}, dcm)
    dcm_keys = keys(dcm.meta)
    pnames = Symbol[basic_properties...]
    for (k, v) in fieldname_dict
        if v in dcm_keys
            push!(pnames, k)
        end
    end
    return pnames
end

Base.setindex!(dcm::DICOMData, val, sym::Symbol) =
    setindex!(dcm.meta, val, fieldname_dict[sym])
Base.setindex!(dcm::DICOMData, val, str::String) =
    setindex!(dcm.meta, val, fieldname_dict[Symbol(str)])
Base.setindex!(dcm::DICOMData, val, tag::Tuple{UInt16,UInt16}) =
    setindex!(dcm.meta, val, tag)

Base.getindex(dcm::DICOMData, sym::Symbol) = lookup(dcm, sym)
Base.getindex(dcm::DICOMData, str::String) = lookup(dcm, str)
Base.getindex(dcm::DICOMData, tag::Tuple{UInt16,UInt16}) = dcm.meta[tag]

Base.get(dcm::DICOMData, key::Tuple{UInt16,UInt16}, default) = get(dcm.meta, key, default)

Base.keys(dcm::DICOMData) = keys(dcm.meta)
Base.haskey(dcm::DICOMData, sym::Symbol) = haskey(dcm.meta, fieldname_dict[sym])
Base.haskey(dcm::DICOMData, str::String) = haskey(dcm.meta, fieldname_dict[Symbol(str)])
Base.haskey(dcm::DICOMData, tag::Tuple{UInt16,UInt16}) = haskey(dcm.meta, tag)

function lookup(dcm::DICOMData, str::String)
    sym = Symbol(filter(x -> !isspace(x), str))
    return lookup(dcm, sym)
end

function lookup(dcm::DICOMData, sym::Symbol)
    return get(dcm.meta, fieldname_dict[sym], nothing)
end

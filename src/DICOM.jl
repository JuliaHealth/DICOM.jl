module DICOM

export dcm_parse, dcm_write, lookup, lookup_vr, rescale!
export @tag_str

"""
    @tag_str(s)

Return the dicom tag, corresponding to the string `s`.
```jldoctest
julia> using DICOM

julia> tag"ROI Mean"
(0x6000, 0x1302)
```
"""
macro tag_str(s)
    DICOM.fieldname_dict[s]
end


# Create dicom dictionary - used for reading/writing DICOM files
# Keys are tuple containing hex Group and Element of DICOM entry
# Stored value is String array: [Field Name, VR, Data Length], e.g:
# Julia> DICOM.dcm_dict[(0x0008,0x0005)]
# 3-element Array{String,1}:
#  "Specific Character Set"
#  "CS"
#  "1-n"
include("dcm_dict.jl")  # const dcm_dict = ...

# For convenience, dictionary to get hex tag from field name, e.g:
# Julia> DICOM.fieldname_dict["Specific Character Set"]
# (0x0008, 0x0005)
fieldname_dict = Dict(val[1] => key for (key, val) in dcm_dict)

# These "empty" values are used internally. They are returned if a search fails.
const empty_vr = "" # Can be any VR that doesn't exist
const empty_vr_lookup = ["", empty_vr, ""] # Used in lookup_vr as failure state
const empty_tag = (0x0000, 0x0000)
const empty_dcm_dict = Dict(DICOM.empty_tag => nothing)

const VR_names = [
    "AE",
    "AS",
    "AT",
    "CS",
    "DA",
    "DS",
    "DT",
    "FL",
    "FD",
    "IS",
    "LO",
    "LT",
    "OB",
    "OF",
    "OW",
    "PN",
    "SH",
    "SL",
    "SQ",
    "SS",
    "ST",
    "TM",
    "UI",
    "UL",
    "UN",
    "US",
    "UT",
]

# mapping UID => bigendian? explicitvr?
const meta_uids = Dict([
    ("1.2.840.10008.1.2", (false, false)),
    ("1.2.840.10008.1.2.1", (false, true)),
    ("1.2.840.10008.1.2.1.99", (false, true)),
    ("1.2.840.10008.1.2.2", (true, true)),
])

"""
    lookup_vr(tag::Tuple{Integer,Integer})

Return VR value for tag from DICOM dictionary

# Example
```jldoctest
julia> lookup_vr((0x0028,0x0004))
"CS"
```
"""
function lookup_vr(gelt::Tuple{UInt16,UInt16})
    if gelt[1] & 0xff00 == 0x5000
        gelt = (0x5000, gelt[2])
    elseif gelt[1] & 0xff00 == 0x6000
        gelt = (0x6000, gelt[2])
    end
    r = get(dcm_dict, gelt, empty_vr_lookup)
    return (r[2])
end

function lookup(d::Dict{Tuple{UInt16,UInt16},Any}, fieldnameString::String)
    return (get(d, fieldname_dict[fieldnameString], nothing))
end

function rescale!(dcm::Dict{Tuple{UInt16,UInt16},Any}, direction = :forward)
    if !haskey(dcm, tag"Rescale Intercept") || !haskey(dcm, tag"Rescale Slope")
        return dcm
    end
    if direction == :forward
        dcm[tag"Pixel Data"] =
            @. dcm[tag"Pixel Data"] * dcm[tag"Rescale Slope"] + dcm[tag"Rescale Intercept"]
    else
        pixel_data = dcm[tag"Pixel Data"]
        @. pixel_data -= dcm[tag"Rescale Intercept"]
        @. pixel_data /= dcm[tag"Rescale Slope"]
        dtype = determine_dtype(dcm)
        dcm[tag"Pixel Data"] = @. convert(dtype, round(pixel_data))
    end
    return dcm
end

if ENDIAN_BOM == 0x04030201
    order(x, endian) = endian == :little ? x : bswap.(x)
else
    order(x, endian) = endian == :big ? x : bswap.(x)
end

always_implicit(grp, elt) =
    (grp == 0xFFFE && (elt == 0xE0DD || elt == 0xE000 || elt == 0xE00D))

"""
   dcm_parse(fn::AbstractString)

Reads file fn and returns a Dict
"""
function dcm_parse(fn::AbstractString; kwargs...)
    st = open(fn)
    dcm = dcm_parse(st; kwargs...)
    close(st)
    dcm
end

"""
   dcm_parse(st::IO)

Reads IO st and returns a Dict
"""
function dcm_parse(
    st::IO;
    return_vr = false,
    preamble = true,
    max_group = 0xffff,
    aux_vr = Dict{Tuple{UInt16,UInt16},String}(),
)
    if preamble
        check_preamble(st)
    end
    dcm = read_meta(st)
    is_explicit, endian = determine_explicitness_and_endianness(dcm)
    file_properties = (is_explicit = is_explicit, endian = endian, aux_vr = aux_vr)
    (dcm, vr) = read_body(st, dcm, file_properties; max_group = max_group)
    if return_vr
        return dcm, vr
    else
        return dcm
    end
end

function check_preamble(st)
   # First 128 can be skipped
    skip(st, 128)
   # "DICM" identifier must be after the first 128 bytes
    sig = String(read!(st, Array{UInt8}(undef, 4)))
    if sig != "DICM"
        error("dicom: invalid file header")
    end
    return
end

# Meta is always explicit VR / little endian
function read_meta(st::IO)
    dcm = Dict{Tuple{UInt16,UInt16},Any}()
    is_explicit = true
    endian = :little
    while true
        pos = position(st)
        (gelt, data, vr) = read_element(st, (is_explicit, endian, empty_dcm_dict))
        grp = gelt[1]
        if grp > 0x0002 || gelt == empty_tag
            seek(st, pos)
            return dcm
        else
            dcm[gelt] = data
        end
    end
    error("Unexpected break from loop while reading preamble")
end

function determine_explicitness_and_endianness(dcm)
   # Default is implicit_vr & little-endian
    if !haskey(dcm, (0x0002, 0x0010))
        return (false, :little)
    end
    metaInfo = get(meta_uids, dcm[(0x0002, 0x0010)], (false, true))
    explicitness = metaInfo[2]
    if metaInfo[1]
        endianness = :big
    else
        endianness = :little
    end
    return explicitness, endianness
end

function read_body(st, dcm, props; max_group)
    vrs = Dict{Tuple{UInt16,UInt16},String}()
    while true
        (gelt, data, vr) = read_element(st, props, dcm)
        if gelt == empty_tag || gelt[1] > max_group
            break
        else
            dcm[gelt] = data
            vrs[gelt] = vr
        end
    end
    return dcm, vrs
end

function read_element(st::IO, props, dcm = empty_dcm_dict)
    (is_explicit, endian, aux_vr) = props
    local grp
    try
        grp = read_group_tag(st, endian)
    catch
        return (empty_tag, 0, empty_vr)
    end
    elt = read_element_tag(st, endian)
    gelt = (grp, elt)
    vr, lentype = determine_vr_and_lentype(st, gelt, is_explicit, aux_vr)
    sz = read_element_size(st, lentype, endian)
   # Empty VR can be supplied in aux_vr to skip an element
    if isempty(vr)
        sz = isodd(sz) ? sz + 1 : sz
        skip(st, sz)
        return (read_element(st::IO, props, dcm))
    end

    data = vr == "ST" || vr == "LT" || vr == "UT" || vr == "AS" ?
        String(read!(st, Array{UInt8}(undef, sz))) :

        sz == 0 || vr == "XX" ? Any[] :

        vr == "SQ" ? sequence_parse(st, sz, props) :

        gelt == (0x7FE0, 0x0010) ? pixeldata_parse(st, sz, vr, dcm, endian) :

        sz == 0xffffffff ? undefined_length(st, vr) :

        vr == "FL" ? numeric_parse(st, Float32, sz, endian) :
        vr == "FD" ? numeric_parse(st, Float64, sz, endian) :
        vr == "SL" ? numeric_parse(st, Int32, sz, endian) :
        vr == "SS" ? numeric_parse(st, Int16, sz, endian) :
        vr == "UL" ? numeric_parse(st, UInt32, sz, endian) :
        vr == "US" ? numeric_parse(st, UInt16, sz, endian) :

        vr == "OB" ? order(read!(st, Array{UInt8}(undef, sz)), endian) :
        vr == "OF" ? order(read!(st, Array{Float32}(undef, div(sz, 4))), endian) :
        vr == "OW" ? order(read!(st, Array{UInt16}(undef, div(sz, 2))), endian) :

        vr == "AT" ?
        [order(read!(st, Array{UInt16}(undef, 2)), endian) for n = 1:div(sz, 4)] :

        vr == "DS" ?
        map(x -> x == "" ? 0.0 : parse(Float64, x), string_parse(st, sz, 16, false)) :
        vr == "IS" ?
        map(x -> x == "" ? 0 : parse(Int, x), string_parse(st, sz, 12, false)) :

        vr == "AE" ? string_parse(st, sz, 16, false) :
        vr == "CS" ? string_parse(st, sz, 16, false) :
        vr == "SH" ? string_parse(st, sz, 16, false) :
        vr == "LO" ? string_parse(st, sz, 64, false) :
        vr == "UI" ? string_parse(st, sz, 64, false) :
        vr == "PN" ? string_parse(st, sz, 64, true) :

        vr == "DA" ? string_parse(st, sz, 10, true) :
        vr == "DT" ? string_parse(st, sz, 26, false) :
        vr == "TM" ? string_parse(st, sz, 16, false) :
        order(read!(st, Array{UInt8}(undef, sz)), endian)

    if isodd(sz) && sz != 0xffffffff
        skip(st, 1)
    end

   # For convenience, get rid of array if it is just acting as a container
   # Exception is "SQ", where array is part of structure
    if length(data) == 1 && vr != "SQ"
        data = data[1]
       # Sometimes it is necessary to go one level deeper
        if length(data) == 1
            data = data[1]
        end
    end

    return (gelt, data, vr)
end

read_group_tag(st, endian) = order(read(st, UInt16), endian)
read_element_tag = read_group_tag
read_element_size(st, lentype, endian) = order(read(st, lentype), endian)

function determine_vr_and_lentype(st, gelt, is_explicit, aux_vr)
    (grp, elt) = gelt
    lentype = UInt32
    if is_explicit && !always_implicit(grp, elt)
        vr = String(read!(st, Array{UInt8}(undef, 2)))
        if vr in ("OB", "OW", "OF", "SQ", "UT", "UN")
            skip(st, 2)
        else
            lentype = UInt16
        end
        diffvr = !isequal(vr, lookup_vr(gelt))
    else
        vr = elt == 0x0000 ? "UL" : lookup_vr(gelt)
    end
    if isodd(grp) && grp > 0x0008 && 0x0010 <= elt < +0x00FF
       # Private creator
        vr = "LO"
    elseif isodd(grp) && grp > 0x0008
       # Assume private
        vr = "UN"
    end
    if haskey(aux_vr, gelt)
        vr = aux_vr[gelt]
    end
    if vr === empty_vr
        if haskey(aux_vr, (0x0000, 0x0000))
            vr = aux_vr[(0x0000, 0x0000)]
        elseif !haskey(aux_vr, gelt)
            error("dicom: unknown tag ", gelt)
        end
    end
    return vr, lentype
end

numeric_parse(st::IO, T::DataType, sz, endian) =
    order(T[read(st, T) for i = 1:div(sz, sizeof(T))], endian)

function string_parse(st, sz, maxlen, spaces)
    endpos = position(st) + sz
    data = [""]
    first = true
    while position(st) < endpos
        c = !first || spaces ? read(st, Char) : skip_spaces(st, endpos)
        if c == '\\'
            push!(data, "")
            first = true
        elseif c == '\0'
            break
        else
            data[end] = string(data[end], c)  # TODO: inefficient
            first = false
        end
    end
    if !spaces
        return map(rstrip, data)
    end
    return data
end

function skip_spaces(st, endpos)
    while true
        c = read(st, Char)
        if c != ' ' || position(st) == endpos
            return c
        end
    end
end

function sequence_parse(st, sz, props)
    (is_explicit, endian, aux_vr) = props
    sq = Array{Dict{Tuple{UInt16,UInt16},Any},1}()
    while sz > 0
        grp = read_group_tag(st, endian)
        elt = read_element_tag(st, endian)
        itemlen = read_element_size(st, UInt32, endian)
        if grp == 0xFFFE && elt == 0xE0DD
            return sq
        end
        if grp != 0xFFFE || elt != 0xE000
            error("dicom: expected item tag in sequence")
        end
        push!(sq, sequence_item(st, itemlen, props))
        sz -= 8 + (itemlen != 0xffffffff) * itemlen
    end
    return sq
end

function sequence_item(st::IO, sz, props)
    item = Dict{Tuple{UInt16,UInt16},Any}()
    endpos = position(st) + sz
    while position(st) < endpos
        (gelt, data, vr) = read_element(st, props, item)
        if isequal(gelt, (0xFFFE, 0xE00D))
            break
        end
        item[gelt] = data
    end
    return item
end

# always little-endian, "encapsulated" iff sz==0xffffffff
function pixeldata_parse(st::IO, sz, vr::String, dcm, endian)
    dtype = determine_dtype(dcm, vr)
    yr = 1
    zr = 1
   # (0028,0010) defines number of rows
    f = get(dcm, (0x0028, 0x0010), nothing)
    if f !== nothing
        yr = Int(f)
    end
   # (0028,0011) defines number of columns
    f = get(dcm, (0x0028, 0x0011), nothing)
    if f !== nothing
        xr = Int(f)
    end
   # (0028,0012) defines number of planes
    f = get(dcm, (0x0028, 0x0012), nothing)
    if f !== nothing
        zr = Int(f)
    end
   # (0028,0008) defines number of frames
    f = get(dcm, (0x0028, 0x0008), nothing)
    if f !== nothing
        zr *= Int(f)
    end
   # (0x0028, 0x0002) defines number of samples per pixel
    f = get(dcm, (0x0028, 0x0002), nothing)
    if f !== nothing
        samples_per_pixel = Int(f)
    else
        samples_per_pixel = 1
    end
    if sz != 0xffffffff
        is_interleaved = get(dcm, (0x0028, 0x0006), nothing) == 0
        if is_interleaved
            data_dims = [samples_per_pixel, xr, yr, zr]
        else
            data_dims = [xr, yr, zr, samples_per_pixel]
        end
        data_dims = data_dims[data_dims.>1]
        data = Array{dtype}(undef, data_dims...)
        read!(st, data)
       # Permute because Julia is column-major while DICOM is row-major
        numdims = ndims(data)
        if numdims == 2
            perm = (2, 1)
        elseif numdims == 3
            perm = is_interleaved ? (3, 2, 1) : (2, 1, 3)
        elseif numdims == 4
            perm = is_interleaved ? (3, 2, 1, 4) : (2, 1, 3, 4)
        end
        data = permutedims(data, perm)
    else
        # start with Basic Offset Table Item
        is_explicit, endian = determine_explicitness_and_endianness(dcm)
        data = Array{Any,1}(read_element(st, (is_explicit, endian, Dict()))[2])
        while true
            grp = read_group_tag(st, endian)
            elt = read_element_tag(st, endian)
            xr = read_element_size(st, UInt32, endian)
            if grp == 0xFFFE && elt == 0xE0DD
                return data
            end
            if grp != 0xFFFE || elt != 0xE000
                error("dicom: expected item tag in encapsulated pixel data")
            end
            if dtype === UInt16
                xr = div(xr, 2)
            end
            push!(data, read!(st, Array{dtype}(undef, xr)))
        end
    end
    return order.(data, endian)
end

function determine_dtype(dcm, vr = "OB")
    # (0x0028,0x0103) defines Pixel Representation
    is_signed = false
    f = get(dcm, (0x0028, 0x0103), nothing)
    if f !== nothing
        # Data is signed if f==1
        is_signed = f == 1
    end
    bit_type = 16
    # (0x0028,0x0100) defines Bits Allocated
    f = get(dcm, (0x0028, 0x0100), nothing)
    if f !== nothing
        bit_type = Int(f)
    else
        f = get(dcm, (0x0028, 0x0101), nothing)
        bit_type = f !== nothing ? Int(f) : vr == "OB" ? 8 : 16
    end
    if bit_type == 8
        dtype = is_signed ? Int8 : UInt8
    else
        dtype = is_signed ? Int16 : UInt16
    end
    return dtype
end

function undefined_length(st, vr)
    data = IOBuffer()
    w1 = w2 = 0
    while true
        # read until 0xFFFE 0xE0DD
        w1 = w2
        w2 = read(st, UInt16)
        if w1 == 0xFFFE
            if w2 == 0xE0DD
                break
            end
            write(data, w1)
        end
        if w2 != 0xFFFE
            write(data, w2)
        end
    end
    skip(st, 4)
    take!(data)
end


function dcm_write(fn::String, d::Dict{Tuple{UInt16,UInt16},Any}; kwargs...)
    st = open(fn, "w+")
    dcm_write(st, d; kwargs...)
    close(st)
    return fn
end

function dcm_write(
    st::IO,
    dcm::Dict{Tuple{UInt16,UInt16},Any};
    preamble = true,
    aux_vr = Dict{Tuple{UInt16,UInt16},String}(),
)
    if preamble
        write(st, zeros(UInt8, 128))
        write(st, "DICM")
    end
    (is_explicit, endian) = determine_explicitness_and_endianness(dcm)
    for gelt in sort(collect(keys(dcm)))
        write_element(st, gelt, dcm[gelt], is_explicit, aux_vr)
    end
    return
end

function write_element(st::IO, gelt::Tuple{UInt16,UInt16}, data, is_explicit, aux_vr)
    if haskey(aux_vr, gelt)
        vr = aux_vr[gelt]
    else
        vr = lookup_vr(gelt)
    end
    if vr === empty_vr
        # Element tags ending in 0x0000 are not included in dcm_dicm.jl, their vr is UL
        if gelt[2] == 0x0000
            vr = "UL"
        elseif isodd(gelt[1]) && gelt[1] > 0x0008 && 0x0010 <= gelt[2] < +0x00FF
                # Private creator
            vr = "LO"
        elseif isodd(gelt[1]) && gelt[1] > 0x0008
                # Assume private
            vr = "UN"
        else
            error("dicom: unknown tag ", gelt)
        end
    end
    if gelt == (0x7FE0, 0x0010)
        return pixeldata_write(st, data, is_explicit)
    end

    if vr == "SQ"
        vr = is_explicit ? vr : empty_vr
        return dcm_store(st, gelt, s -> sequence_write(s, data, is_explicit), vr)
    end

    # Pack data into array container. This is to undo "data = data[1]" from read_element().
    if !isa(data, Array) && vr in ("FL", "FD", "SL", "SS", "UL", "US")
        data = [data]
    end

    data = isempty(data) ? UInt8[] :
        vr in ("OB", "OF", "OW", "ST", "LT", "UT") ? data :
        vr in ("AE", "CS", "SH", "LO", "UI", "PN", "DA", "DT", "TM") ?
        string_write(data, 0) :
        vr == "FL" ? convert(Array{Float32,1}, data) :
        vr == "FD" ? convert(Array{Float64,1}, data) :
        vr == "SL" ? convert(Array{Int32,1}, data) :
        vr == "SS" ? convert(Array{Int16,1}, data) :
        vr == "UL" ? convert(Array{UInt32,1}, data) :
        vr == "US" ? convert(Array{UInt16,1}, data) :
        vr == "AT" ? [data...] :
        vr in ("DS", "IS") ? string_write(map(string, data), 0) : data

    if !is_explicit && gelt[1] > 0x0002
        vr = empty_vr
    end

    dcm_store(st, gelt, s -> write(s, data), vr)
end

string_write(vals::Array{SubString{String}}, maxlen) =
    string_write(convert(Array{String}, vals), maxlen)
string_write(vals::SubString{String}, maxlen) = string_write(convert(String, vals), maxlen)
string_write(vals::Tuple{String,String}, maxlen) = string_write(collect(vals), maxlen)
string_write(vals::Char, maxlen) = string_write(string(vals), maxlen)
string_write(vals::String, maxlen) = string_write([vals], maxlen)
string_write(vals::Array{String,1}, maxlen) = join(vals, '\\')

dcm_store(st::IO, gelt::Tuple{UInt16,UInt16}, writef::Function) =
    dcm_store(st, gelt, writef, empty_vr)
function dcm_store(st::IO, gelt::Tuple{UInt16,UInt16}, writef::Function, vr::String)
    lentype = UInt32
    write(st, UInt16(gelt[1])) # Grp
    write(st, UInt16(gelt[2])) # Elt
    if vr !== empty_vr
        write(st, vr)
        if vr in ("OB", "OW", "OF", "SQ", "UT", "UN")
            write(st, UInt16(0))
        else
            lentype = UInt16
        end
    end
    # Write data first, then calculate length, then go back to write length
    p = position(st)
    write(st, zero(lentype)) # Placeholder for the data length
    writef(st)
    endp = position(st)
    # Remove placeholder's length, either 2 (UInt16) or 4 (UInt32) steps (1 step = 8 bits)
    if lentype == UInt32
        sz = endp - p - 4
    else
        sz = endp - p - 2
    end
    szWasOdd = isodd(sz) # If length is odd, round up - UInt8(0) will be written at end
    if szWasOdd
        sz += 1
    end
    seek(st, p)
    write(st, convert(lentype, max(0, sz)))
    seek(st, endp)
    if szWasOdd
        write(st, UInt8(0))
    end
end

sequence_write(st::IO, items::Array{Any,1}, evr::Bool) = sequence_write(st,convert(Array{Dict{Tuple{UInt16,UInt16},Any},1},items),evr)
function sequence_write(st::IO, items::Array{Dict{Tuple{UInt16,UInt16},Any},1}, evr)
    for subitem in items
        if length(subitem) > 0
            dcm_store(st, (0xFFFE, 0xE000), s -> sequence_item_write(s, subitem, evr))
        end
    end
    write(st, UInt16[0xFFFE, 0xE0DD, 0x0000, 0x0000])
end

function sequence_item_write(st::IO, items::Dict{Tuple{UInt16,UInt16},Any}, evr)
    for gelt in sort(collect(keys(items)))
        write_element(st, gelt, items[gelt], evr, empty_dcm_dict)
    end
    write(st, UInt16[0xFFFE, 0xE00D, 0x0000, 0x0000])
end

function pixeldata_write(st, d, evr)
    # if length(el) > 1
    #     error("dicom: compression not supported")
    # end
    nt = eltype(d)
    vr = nt === UInt8 || nt === Int8 ? "OB" :
        nt === UInt16 || nt === Int16 ? "OW" :
        nt === Float32 ? "OF" : error("dicom: unsupported pixel format")
    # Permute because Julia is column-major while DICOM is row-major
    # !warn! This part assumes that Planar Configuration (tag: 0x0028, 0x0006) is not 0
    numdims = ndims(d)
    perm = numdims == 2 ? (2, 1) : numdims == 3 ? (2, 1, 3) : (2, 1, 3, 4)
    d = permutedims(d, perm)
    if evr !== false
        dcm_store(st, (0x7FE0, 0x0010), s -> write(s, d), vr)
    elseif vr != "OW"
        error("dicom: implicit VR only supports 16-bit pixels")
    else
        dcm_store(st, (0x7FE0, 0x0010), s -> write(s, d))
    end
end

end

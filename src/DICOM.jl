module DICOM

export dcm_parse, dcm_write, lookup, lookup_vr
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
const emptyVR = "" # Can be any VR that doesn't exist
const emptyVR_lookup = ["", emptyVR, ""] # Used in lookup_vr as failure state
const emptyTag = (0x0000,0x0000)
const emptyDcmDict = Dict(DICOM.emptyTag => nothing)

const VR_names = [ "AE","AS","AT","CS","DA","DS","DT","FL","FD","IS","LO","LT","OB","OF",
       "OW","PN","SH","SL","SQ","SS","ST","TM","UI","UL","UN","US","UT" ]

# mapping UID => bigendian? explicitvr?
const meta_uids = Dict([("1.2.840.10008.1.2", (false, false)),
                  ("1.2.840.10008.1.2.1", (false, true)),
                  ("1.2.840.10008.1.2.1.99", (false, true)),
                  ("1.2.840.10008.1.2.2", (true, true))]);

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
    if gelt[1]&0xff00 == 0x5000
        gelt = (0x5000,gelt[2])
    elseif gelt[1]&0xff00 == 0x6000
        gelt = (0x6000,gelt[2])
    end
    r = get(dcm_dict, gelt, emptyVR_lookup)
    return(r[2])
end

function lookup(d::Dict{Tuple{UInt16,UInt16},Any}, fieldnameString::String)
    return(get(d, fieldname_dict[fieldnameString], nothing))
end

always_implicit(grp, elt) = (grp == 0xFFFE && (elt == 0xE0DD||elt == 0xE000||
                                               elt == 0xE00D))


dcm_store(st::IO, gelt::Tuple{UInt16,UInt16}, writef::Function) = dcm_store(st, gelt, writef, emptyVR)
function dcm_store(st::IO, gelt::Tuple{UInt16,UInt16}, writef::Function, vr::String)
    lentype = UInt32
    write(st, UInt16(gelt[1])) # Grp
    write(st, UInt16(gelt[2])) # Elt
    if vr !== emptyVR
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
        sz = endp-p-4
    else
        sz = endp-p-2
    end
    szWasOdd = isodd(sz) # If length is odd, round up - UInt8(0) will be written at end
    if szWasOdd
        sz+=1
    end
    seek(st, p)
    write(st, convert(lentype, max(0,sz)))
    seek(st, endp)
    if szWasOdd
        write(st, UInt8(0))
    end
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

<<<<<<< HEAD
function sequence_item(st::IO, evr, sz)
=======

function sequence_item(st::IOStream, evr, sz,endian)
>>>>>>> 5f0a7db7c88445881eeab22fda25863c32a41292
    item = Dict{Tuple{UInt16,UInt16},Any}()
    endpos = position(st) + sz
    while position(st) < endpos
          (gelt, data, vr) = element(st, evr,endian)
        if isequal(gelt, (0xFFFE,0xE00D))
            break
        end
        item[gelt] = data
    end
    return item
end

function sequence_item_write(st::IO, evr::Bool, items::Dict{Tuple{UInt16,UInt16},Any})
    for gelt in sort(collect(keys(items)))
        element_write(st, evr, gelt, items[gelt])
    end
    write(st, UInt16[0xFFFE, 0xE00D, 0x0000, 0x0000])
end

function sequence_parse(st, evr, sz,endian)
    sq = Array{Dict{Tuple{UInt16,UInt16},Any},1}()
    while sz > 0
        grp = order(read(st, UInt16), endian)
        elt = order(read(st, UInt16), endian)
        itemlen = order(read(st, UInt32), endian)
        if grp==0xFFFE && elt==0xE0DD
            return sq
        end
        if grp != 0xFFFE || elt != 0xE000
            error("dicom: expected item tag in sequence")
        end
        push!(sq, sequence_item(st, evr, itemlen, endian))
        sz -= 8 + (itemlen != 0xffffffff) * itemlen
    end
    return sq
end

function sequence_write(st::IO, evr::Bool, items::Array{Dict{Tuple{UInt16,UInt16},Any},1})
    for subitem in items
        if length(subitem) > 0
            dcm_store(st, (0xFFFE,0xE000), s->sequence_item_write(s, evr, subitem))
        end
    end
    write(st, UInt16[0xFFFE, 0xE0DD, 0x0000, 0x0000])
end

# always little-endian, "encapsulated" iff sz==0xffffffff
function pixeldata_parse(st::IO, sz, vr::String, dcm=emptyDcmDict)
    # (0x0028,0x0103) defines Pixel Representation
    isSigned = false
    f = get(dcm, (0x0028,0x0103), nothing)
    if f !== nothing
        # Data is signed if f==1
        isSigned = f == 1
    end
    # (0x0028,0x0100) defines Bits Allocated
    bitType = 16
    f = get(dcm, (0x0028,0x0100), nothing)
    if f !== nothing
        bitType = Int(f)
    else
        f = get(dcm, (0x0028,0x0101), nothing)
        bitType = f !== nothing ? Int(f) :
            vr == "OB" ? 8 : 16
    end
    if bitType == 8
        dtype = isSigned ? Int8 : UInt8
    else
        dtype = isSigned ? Int16 : UInt16
    end
    yr=1
    zr=1
    # (0028,0010) defines number of rows
    f = get(dcm, (0x0028,0x0010), nothing)
    if f !== nothing
        xr = Int(f)
    end
    # (0028,0011) defines number of columns
    f = get(dcm, (0x0028,0x0011), nothing)
    if f !== nothing
        yr = Int(f)
    end
    # (0028,0012) defines number of planes
    f = get(dcm, (0x0028,0x0012), nothing)
    if f !== nothing
        zr = Int(f)
    end
    # (0028,0008) defines number of frames
    f = get(dcm, (0x0028,0x0008), nothing)
    if f !== nothing
        zr *= Int(f)
    end
    if sz != 0xffffffff
        data =
        zr > 1 ? Array{dtype}(undef, xr, yr, zr) : Array{dtype}(undef, xr, yr)
        read!(st, data)
    else
        # start with Basic Offset Table Item
        data = Array{Any,1}(element(st, false)[2])
        while true
            grp = read(st, UInt16)
            elt = read(st, UInt16)
            xr = read(st, UInt32)
            if grp == 0xFFFE && elt == 0xE0DD
                return data
            end
            if grp != 0xFFFE || elt != 0xE000
                error("dicom: expected item tag in encapsulated pixel data")
            end
            if dtype === UInt16; xr = div(xr,2); end
            push!(data, read!(st, Array{dtype}(undef, xr)))
        end
    end
    return data
end

function pixeldata_write(st, evr, d)
    # if length(el) > 1
    #     error("dicom: compression not supported")
    # end
    nt = eltype(d)
    vr = nt === UInt8  || nt === Int8  ? "OB" :
         nt === UInt16 || nt === Int16 ? "OW" :
         nt === Float32                ? "OF" :
         error("dicom: unsupported pixel format")
    if evr !== false
        dcm_store(st, (0x7FE0,0x0010), s->write(s,d), vr)
    elseif vr != "OW"
        error("dicom: implicit VR only supports 16-bit pixels")
    else
        dcm_store(st, (0x7FE0,0x0010), s->write(s,d))
    end
end

function skip_spaces(st, endpos)
    while true
        c = read(st,Char)
        if c != ' ' || position(st) == endpos
            return c
        end
    end
    return '\0'
end

function string_parse(st, sz, maxlen, spaces)
    endpos = position(st)+sz
    data = [ "" ]
    first = true
    while position(st) < endpos
        c = !first||spaces ? read(st,Char) : skip_spaces(st, endpos)
        if c == '\\'
            push!(data, "")
            first = true
        elseif c == '\0'
            break
        else
            data[end] = string(data[end],c)  # TODO: inefficient
            first = false
        end
    end
    if !spaces
        return map(rstrip,data)
    end
    return data
end

numeric_parse(st::IO, T::DataType, sz) = T[read(st, T) for i=1:div(sz,sizeof(T))]

<<<<<<< HEAD
function element(st::IO, evr::Bool, dcm=emptyDcmDict, dVR=Dict{Tuple{UInt16,UInt16},String}())
=======

if ENDIAN_BOM == 0x04030201
  order(x, endian) = endian == :little ? x : bswap.(x)
else
  order(x, endian) = endian == :big ? x : bswap.(x)
end

function element(st::IOStream, evr::Bool, endian=:little, dcm=emptyDcmDict, dVR=Dict{Tuple{UInt16,UInt16},String}())
>>>>>>> 5f0a7db7c88445881eeab22fda25863c32a41292
    lentype = UInt32
    diffvr = false
    local grp
    try
        grp = read(st, UInt16)
    catch
        return(emptyTag,0,emptyVR)
    end
    if grp <= 0x0002
<<<<<<< HEAD
=======
        endian = :little
>>>>>>> 5f0a7db7c88445881eeab22fda25863c32a41292
        evr = true
    end
    grp = order(grp, endian)
    elt = order(read(st, UInt16), endian)
    gelt = (grp,elt)
    if evr && !always_implicit(grp,elt)
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
    if isodd(grp) && grp > 0x0008 && 0x0010 <= elt <+ 0x00FF
        # Private creator
        vr = "LO"
    elseif isodd(grp) && grp > 0x0008
        # Assume private
        vr = "UN"
    end
    if haskey(dVR, gelt)
        vr = dVR[gelt]
    end
    if vr === emptyVR
        if haskey(dVR, (0x0000,0x0000))
            vr = dVR[(0x0000,0x0000)]
        elseif !haskey(dVR, gelt)
            error("dicom: unknown tag ", gelt)
        end
    end

    sz = order(read(st,lentype), endian)

    # Empty VR can be supplied in dVR to skip an element
    if vr == ""
        sz = isodd(sz) ? sz+1 : sz
        skip(st,sz)
        return(element(st,evr,endian,dcm,dVR))
    end

    data =
    vr=="ST" || vr=="LT" || vr=="UT" || vr=="AS" ? String(read!(st, Array{UInt8}(undef, sz))) :

    sz==0 || vr=="XX" ? Any[] :

    vr == "SQ" ? sequence_parse(st, evr, sz, endian) :

    gelt == (0x7FE0,0x0010) ? pixeldata_parse(st, sz, vr, dcm) :

    sz == 0xffffffff ? undefined_length(st, vr) :

    vr == "FL" ? order(numeric_parse(st, Float32, sz), endian) :
    vr == "FD" ? order(numeric_parse(st, Float64, sz), endian) :
    vr == "SL" ? order(numeric_parse(st, Int32  , sz), endian) :
    vr == "SS" ? order(numeric_parse(st, Int16  , sz), endian) :
    vr == "UL" ? order(numeric_parse(st, UInt32 , sz), endian) :
    vr == "US" ? order(numeric_parse(st, UInt16 , sz), endian) :

    vr == "OB" ? order(read(st, UInt8  , sz),endian)        :
    vr == "OF" ? order(read(st, Float32, div(sz,4)), endian) :
    vr == "OW" ? order(read(st, UInt16 , div(sz,2)), endian) :

    vr == "AT" ? [ order(read(st,UInt16,2), endian) for n=1:div(sz,4) ] :

    vr == "AT" ? [ read!(st, Array{UInt16}(undef, 2)) for n=1:div(sz,4) ] :

    vr == "DS" ? map(x->x=="" ? 0. : parse(Float64,x), string_parse(st, sz, 16, false)) :
    vr == "IS" ? map(x->x=="" ? 0  : parse(Int,x), string_parse(st, sz, 12, false)) :

    vr == "AE" ? string_parse(st, sz, 16, false) :
    vr == "CS" ? string_parse(st, sz, 16, false) :
    vr == "SH" ? string_parse(st, sz, 16, false) :
    vr == "LO" ? string_parse(st, sz, 64, false) :
    vr == "UI" ? string_parse(st, sz, 64, false) :
    vr == "PN" ? string_parse(st, sz, 64, true)  :

    vr == "DA" ? string_parse(st, sz, 10, true) :
    vr == "DT" ? string_parse(st, sz, 26, false) :
    vr == "TM" ? string_parse(st, sz, 16, false) :
    read!(st, Array{UInt8}(undef, sz))

    if isodd(sz) && sz != 0xffffffff
        skip(st, 1)
    end

    # For convenience, get rid of array if it is just acting as a container
    # Exception is "SQ", where array is part of structure
    if length(data) == 1 && vr != "SQ"
        data = data[1]
        if length(data) == 1
            data = data[1]
        end
    end

    # Return vr by default
    return(gelt, data, vr)
end

# todo: support maxlen
string_write(vals::Array{SubString{String}}, maxlen) = string_write(convert(Array{String}, vals), maxlen)
string_write(vals::SubString{String}, maxlen) = string_write(convert(String, vals), maxlen)
string_write(vals::Tuple{String, String}, maxlen) = string_write(collect(vals), maxlen)
string_write(vals::Char, maxlen) = string_write(string(vals), maxlen)
string_write(vals::String, maxlen) = string_write([vals], maxlen)
string_write(vals::Array{String,1}, maxlen) = join(vals, '\\')

element_write(st::IO, evr::Bool, gelt::Tuple{UInt16,UInt16}, data::Any) = element_write(st,evr,gelt,data,lookup_vr(gelt))
function element_write(st::IO, evr::Bool, gelt::Tuple{UInt16,UInt16}, data::Any, vr::String)
    if vr === emptyVR
        # Element tags ending in 0x0000 are not included in dcm_dicm.jl, their vr is UL
        if gelt[2] == 0x0000
            vr = "UL"
        elseif isodd(gelt[1]) && gelt[1] > 0x0008 && 0x0010 <= gelt[2] <+ 0x00FF
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
        return pixeldata_write(st, evr, data)
    end

    if vr == "SQ"
        vr = evr ? vr : emptyVR
        return dcm_store(st, gelt,
                         s->sequence_write(s, evr, data), vr)
    end

    # Pack data into array container. This is to undo "data = data[1]" from element().
    if !isa(data,Array) && vr in ("FL","FD","SL","SS","UL","US")
        data = [data]
    end

    data =
    isempty(data) ? UInt8[] :
    vr in ("OB","OF","OW","ST","LT","UT") ? data :
    vr in ("AE", "CS", "SH", "LO", "UI", "PN", "DA", "DT", "TM") ?
        string_write(data, 0) :
    vr == "FL" ? convert(Array{Float32,1}, data) :
    vr == "FD" ? convert(Array{Float64,1}, data) :
    vr == "SL" ? convert(Array{Int32,1},   data) :
    vr == "SS" ? convert(Array{Int16,1},   data) :
    vr == "UL" ? convert(Array{UInt32,1},  data) :
    vr == "US" ? convert(Array{UInt16,1},  data) :
    vr == "AT" ? [data...] :
    vr in ("DS","IS") ? string_write(map(string,data), 0) :
    data

    if evr === false && gelt[1]>0x0002
        vr = emptyVR
    end

    dcm_store(st, gelt, s->write(s, data), vr)
end

"""
    dcm_parse(fn::AbstractString)

Reads file fn and returns a Dict
"""
function dcm_parse(fn::AbstractString, giveVR=false; header=true, maxGrp=0xffff, dVR=Dict{Tuple{UInt16,UInt16},String}())
    st = open(fn)
    dcm = dcm_parse(st, giveVR; header=header, maxGrp=maxGrp, dVR=dVR)
    close(st)
    dcm
end

"""
    dcm_parse(st::IO)

Reads IO st and returns a Dict
"""
function dcm_parse(st::IO, giveVR=false; header=true, maxGrp=0xffff, dVR=Dict{Tuple{UInt16,UInt16},String}())
    if header
        # First 128 bytes are preamble - should be skipped
        skip(st, 128)
        # "DICM" identifier must be after preamble
        sig = String(read!(st,Array{UInt8}(undef, 4)))
        if sig != "DICM"
            error("dicom: invalid file header")
            # seek(st, 0)
        end
    end
    # a bit of a hack to detect explicit VR. seek past the first tag,
    # and check to see if a valid VR name is there
    skip(st, 4)
    sig = String(read!(st,Array{UInt8}(undef, 2)))
    evr = sig in VR_names
    skip(st, -6)
    dcm = Dict{Tuple{UInt16,UInt16},Any}()
    if giveVR
        dcmVR = Dict{Tuple{UInt16,UInt16},String}()
    end
    endian = :little
    while true
        (gelt, data, vr) = element(st, evr, endian, dcm, dVR) # element(st, evr, dcm, dVR)
        if gelt === emptyTag || gelt[1] > maxGrp
            break
        else
            dcm[gelt] = data
            if giveVR
                dcmVR[gelt] = vr
            end
        end
        # look for transfer syntax UID
        if gelt == (0x0002,0x0010)
            # Default is endian=little, explicitVR=true
            metaInfo = get(meta_uids, data, (false, true))
            evr = metaInfo[2]
            if metaInfo[1]
                endian = :big
            else
                endian = :little
            end
        end
    end
    if giveVR
        return(dcm,dcmVR)
    else
        return(dcm)
    end
end

dcm_write(fn::String, d::Dict{Tuple{UInt16,UInt16},Any}, dVR=Dict{Tuple{UInt16,UInt16},String}()) = dcm_write(open(fn,"w+"),d,dVR)
function dcm_write(st::IO, d::Dict{Tuple{UInt16,UInt16},Any}, dVR=Dict{Tuple{UInt16,UInt16},String}())
    write(st, zeros(UInt8, 128))
    write(st, "DICM")
    # If no dictionary containing VRs is provided, then assume implicit VR - at first
    evr = !isempty(dVR)
    if !haskey(d,(0x0002,0x0010))
        # Insert UID for our transfer syntax, if it doesn't exist
        if evr
            element_write(st, evr, (0x0002,0x0010), "1.2.840.10008.1.2.1", "UI")
        else
            element_write(st, evr, (0x0002,0x0010), "1.2.840.10008.1.2", "UI")
        end
    else
        # Otherwise, use existing transfer UID, and overwrite evr accordingly
        metaInfo = get(meta_uids, d[(0x0002,0x0010)], (false, true))
        evr = metaInfo[2]
    end
    # dVR is only used if it isn't empty and evr=true
    if evr && !isempty(dVR)
        for gelt in sort(collect(keys(d)))
            # dVR only needs to contain keys for cases where lookup_vr() fails
            haskey(dVR, gelt) ? element_write(st, evr, gelt, d[gelt], dVR[gelt]) :
                element_write(st, evr, gelt, d[gelt])
        end
    else
        for gelt in sort(collect(keys(d)))
            element_write(st, evr, gelt, d[gelt])
        end
    end
    close(st)
end

end

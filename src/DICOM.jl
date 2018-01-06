module DICOM

include("dcm_dict.jl")

export dcm_parse, dcm_write, lookup, lookup_vr

function dcm_init()
    dcm_dict = Dict()
    for d in (_dcmdict_data_::Array{Any,1})
        dcm_dict[(UInt16(d[1][1]),UInt16(d[1][2]))] = d[2:end]
    end
    dcm_dict
end

# Dict for looking up DICOM Tag (Tuple) from the fieldname (String)
function fieldname_init()
    fieldname_dict = Dict{AbstractString, Tuple{UInt16,UInt16}}()
    for d in (_dcmdict_data_::Array{Any,1})
        fieldname_dict[d[2]] = (UInt16(d[1][1]),UInt16(d[1][2]))
    end
    return(fieldname_dict)
end

const dcm_dict = dcm_init()
const fieldname_dict = fieldname_init()
_dcmdict_data_ = 0

"""
    lookup_vr(tag::Tuple{Integer,Integer})
    
Return VR value for tag from DICOM dictionary

# Example
```jldoctest
julia> lookup_vr((0x0028,0x0004))
"CS"
```
"""
function lookup_vr(gelt::Tuple{Integer,Integer})
    if gelt[1]&0xff00 == 0x5000
        gelt = (0x5000,gelt[2])
    elseif gelt[1]&0xff00 == 0x6000
        gelt = (0x6000,gelt[2])
    end
    r = get(dcm_dict, gelt, false)
    r !== false && r[2]
end

type DcmElt
    tag::(Tuple{UInt16,UInt16})
    data::Array{Any,1}
    vr::String    # "" except for non-standard VR
    DcmElt(tag, data) = new(tag,data,"")
end

# takes dcm and tag (specify type?)
function lookup(d, t::Tuple)
    for el in d
        if isequal(el.tag,t)
            return el
        end
    end
    return false
end

function lookup(d, fieldnameString::String)
    return(lookup(d, fieldname_dict[fieldnameString]))
end

always_implicit(grp, elt) = (grp == 0xFFFE && (elt == 0xE0DD||elt == 0xE000||
                                               elt == 0xE00D))

VR_names = [ "AE","AS","AT","CS","DA","DS","DT","FL","FD","IS","LO","LT","OB","OF",
       "OW","PN","SH","SL","SQ","SS","ST","TM","UI","UL","UN","US","UT" ]

# mapping UID => bigendian? explicitvr?
meta_uids = Dict([("1.2.840.10008.1.2", (false, false)),
                  ("1.2.840.10008.1.2.1", (false, true)),
                  ("1.2.840.10008.1.2.1.99", (false, true)),
                  ("1.2.840.10008.1.2.2", (true, true))])

dcm_store(st, grp, elt, writef) = dcm_store(st, grp, elt, writef, false)
function dcm_store(st, grp, elt, writef, vr)
    lentype = UInt32
    write(st, UInt16(grp))
    write(st, UInt16(elt))
    if vr !== false
        write(st, vr)
        if vr in ("OB", "OW", "OF", "SQ", "UT", "UN")
            write(st, UInt16(0))
        else
            lentype = UInt16
        end
    end
    p = position(st)
    write(st, zero(lentype))
    writef(st)
    endp = position(st)
    sz = endp-p-4
    seek(st, p)
    write(st, convert(lentype, sz))
    seek(st, endp)
    if isodd(sz)
        write(st, UInt8(0))
    end
end

function undefined_length(st, vr)
    data = memio()
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
    takebuf_array(data)
end

function sequence_item(st, evr, sz)
    item = Any[]
    endpos = position(st) + sz
    while position(st) < endpos
        elt = element(st, evr)
        if isequal(elt.tag, (0xFFFE,0xE00D))
            break
        end
        push!(item, elt)
    end
    return item
end

function sequence_item_write(st, evr, item)
    for el in item
        element_write(st, evr, el)
    end
    write(st, UInt16[0xFFFE, 0xE00D, 0x0000, 0x0000])
end

function sequence_parse(st, evr, sz)
    sq = Any[]
    while sz > 0
        grp = read(st, UInt16)
        elt = read(st, UInt16)
        itemlen = read(st, UInt32)
        if grp==0xFFFE && elt==0xE0DD
            return sq
        end
        if grp != 0xFFFE || elt != 0xE000
            error("dicom: expected item tag in sequence")
        end
        push!(sq, sequence_item(st, evr, itemlen))
        sz -= 8 + (itemlen != 0xffffffff) * itemlen
    end
    return sq
end

function sequence_write(st, evr, item)
    for el in item
        dcm_store(st, 0xFFFE, 0xE000, s->sequence_item_write(s, evr, el))
    end
    write(st, UInt16[0xFFFE, 0xE0DD, 0x0000, 0x0000])
end

# always little-endian, "encapsulated" iff sz==0xffffffff
pixeldata_parse(st, sz, vr) = pixeldata_parse(st, sz, vr, false)
function pixeldata_parse(st, sz, vr, dcm)
    yr=1
    zr=1
    if vr=="OB"
        xr = sz
        dtype = UInt8
    else
        xr = div(sz,2)
        dtype = UInt16
    end
    if dcm !== false
	# (0028,0010) defines number of rows
        f = lookup(dcm, (0x0028,0x0010))
        if f !== false
            xr = f.data[1][1]
        end
	# (0028,0011) defines number of columns
        f = lookup(dcm, (0x0028,0x0011))
        if f !== false
            yr = f.data[1][1]
        end
	# (0028,0012) defines number of planes
        f = lookup(dcm, (0x0028,0x0012))
        if f !== false
            zr = f.data[1][1]
        end
    end
    if sz != 0xffffffff
        data = Array{dtype}(xr, yr, zr)
        read!(st, data)
    else
        # start with Basic Offset Table Item
        data = Array{Any,1}(element(st, false))
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
            push!(data, read!(st, Array(dtype, xr)))
        end
    end
    return data
end

function pixeldata_write(st, evr, el)
    if length(el) > 1
        error("dicom: compression not supported")
    end
    d = el[1]
    nt = eltype(d)
    vr = nt === UInt8  || nt === Int8  ? "OB" :
         nt === UInt16 || nt === Int16 ? "OW" :
         nt === Float32                ? "OF" :
         error("dicom: unsupported pixel format")
    if evr !== false
        dcm_store(st, 0x7FE0, 0x0010, s->write(s,d), vr)
    elseif vr != "OW"
        error("dicom: implicit VR only supports 16-bit pixels")
    else
        dcm_store(st, 0x7FE0, 0x0010, s->write(s,d))
    end
end

function skip_spaces(st)
    while true
        c = read(st,Char)
        if c != ' '
            return c
        end
    end
end

function string_parse(st, sz, maxlen, spaces)
    endpos = position(st)+sz
    data = [ "" ]
    first = true
    while position(st) < endpos
        c = !first||spaces ? read(st,Char) : skip_spaces(st)
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

numeric_parse(st, T, sz) = [read(st, T) for i=1:div(sz,sizeof(T))]

# used internally to take a stream st that is reading a DICOM header
# returns DcmElt
element(st, evr) = element(st, evr, false)
function element(st, evr, dcm)
    lentype = UInt32
    diffvr = false
    local grp
    try
        grp = read(st, UInt16)
    catch
        return false
    end
    elt = read(st, UInt16)
    gelt = (grp,elt)
    if evr && !always_implicit(grp,elt)
        vr = String(read(st, UInt8, 2))
        if vr in ("OB", "OW", "OF", "SQ", "UT", "UN")
            skip(st, 2)
        else
            lentype = UInt16
        end
        diffvr = !isequal(vr, lookup_vr(gelt))
    else
        vr = lookup_vr(gelt)
    end
    if isodd(grp) && grp > 0x0008 && 0x0010 <= elt <+ 0x00FF
        # Private creator
        vr = "LO"
    elseif isodd(grp) && grp > 0x0008
        # Assume private
        vr = "UN"
    end
    if vr === false
        error("dicom: unknown tag ", gelt)
    end

    sz = read(st,lentype)

    data =
    vr=="ST" || vr=="LT" || vr=="UT" ? string(read(st, UInt8, sz)) :

    sz==0 || vr=="XX" ? Any[] :

    vr == "SQ" ? sequence_parse(st, evr, sz) :

    gelt == (0x7FE0,0x0010) ? pixeldata_parse(st, sz, vr, dcm) :

    sz == 0xffffffff ? undefined_length(st, vr) :

    vr == "FL" ? numeric_parse(st, Float32, sz) :
    vr == "FD" ? numeric_parse(st, Float64, sz) :
    vr == "SL" ? numeric_parse(st, Int32  , sz) :
    vr == "SS" ? numeric_parse(st, Int16  , sz) :
    vr == "UL" ? numeric_parse(st, UInt32 , sz) :
    vr == "US" ? numeric_parse(st, UInt16 , sz) :

    vr == "OB" ? read(st, UInt8  , sz)        :
    vr == "OF" ? read(st, Float32, div(sz,4)) :
    vr == "OW" ? read(st, UInt16 , div(sz,2)) :

    vr == "AT" ? [ read(st,UInt16,2) for n=1:div(sz,4) ] :

    vr == "AS" ? String(read(st,UInt8,4)) :

    vr == "DS" ? map(x->parse(Float64,x), string_parse(st, sz, 16, false)) :
    vr == "IS" ? map(x->parse(Int,x), string_parse(st, sz, 12, false)) :

    vr == "AE" ? string_parse(st, sz, 16, false) :
    vr == "CS" ? string_parse(st, sz, 16, false) :
    vr == "SH" ? string_parse(st, sz, 16, false) :
    vr == "LO" ? string_parse(st, sz, 64, false) :
    vr == "UI" ? string_parse(st, sz, 64, false) :
    vr == "PN" ? string_parse(st, sz, 64, true)  :

    vr == "DA" ? string_parse(st, sz, 10, true) :
    vr == "DT" ? string_parse(st, sz, 26, false) :
    vr == "TM" ? string_parse(st, sz, 16, false) :
    read(st, UInt8, sz)

    if isodd(sz) && sz != 0xffffffff
        skip(st, 1)
    end
    delt = DcmElt(gelt, isa(data,Vector{Any}) ? data : Any[ data ])
    if diffvr
        # record non-standard VR
        delt.vr = vr
    end
    return delt
end

# todo: support maxlen
string_write(vals, maxlen) = join(vals, '\\')

function element_write(st, evr, el::DcmElt)
    gelt = el.tag
    if el.vr != ""
        vr = el.vr
    else
        vr = lookup_vr(el.tag)
        if vr === false
            error("dicom: unknown tag ", gelt)
        end
    end
    if el.tag == (0x7FE0, 0x0010)
        return pixeldata_write(st, evr, el.data)
    end
    if evr !== false
        evr = vr
    end
    el = el.data
    if vr == "SQ"
        return dcm_store(st, gelt[1], gelt[2],
                         s->sequence_write(s, evr, el), evr)
    end
    data =
    isempty(el) ? UInt8[] :
    vr in ("OB","OF","OW","ST","LT","UT") ? el[1] :
    vr in ("AE", "CS", "SH", "LO", "UI", "PN", "DA", "DT", "TM") ?
        string_write(el, 0) :
    vr == "FL" ? convert(Array{Float32,1}, el) :
    vr == "FD" ? convert(Array{Float64,1}, el) :
    vr == "SL" ? convert(Array{Int32,1},   el) :
    vr == "SS" ? convert(Array{Int16,1},   el) :
    vr == "UL" ? convert(Array{UInt32,1},  el) :
    vr == "US" ? convert(Array{UInt16,1},  el) :
    vr == "AT" ? [el...] :
    vr in ("DS","IS") ? string_write(map(string,el), 0) :
    el[1]

    dcm_store(st, gelt[1], gelt[2], s->write(s, data), evr)
end

"""
    dcm_parse(fn::AbstractString)
    
Reads file fn and returns an Array of DcmElt 
"""
function dcm_parse(fn::AbstractString)
    st = open(fn)
    evr = false
    skip(st, 128)
    sig = String(read(st,UInt8,4))
    if sig != "DICM"
        error("dicom: invalid file header")
        # seek(st, 0)
    end
    # a bit of a hack to detect explicit VR. seek past the first tag,
    # and check to see if a valid VR name is there
    skip(st, 4)
    sig = String(read(st,UInt8,2))
    evr = sig in VR_names
    skip(st, -6)
    data = Any[]
    while true
        fld = element(st, evr, data)
        if fld === false
            return data
        else
            push!(data, fld)
        end
        # look for transfer syntax UID
        if fld.tag == (0x0002,0x0010)
            fld = get(meta_uids, fld.data[1], false)
            if fld !== false
                evr = fld[2]
                if fld[1]
                    # todo: set byte order to big
                else
                    # todo: set byte order to little
                end
            end
        end
    end
    close(st)
    return data
end

function dcm_write(st, d)
    write(st, zeros(UInt8, 128))
    write(st, "DICM")
    # if any elements specify a VR then use explicit VR syntax
    evr = anyp(x->x.vr!="", d)
    # insert UID for our transfer syntax
    if evr
        element_write(st, evr, DcmElt((0x0002,0x0010),[ "1.2.840.10008.1.2.1" ]))
    else
        element_write(st, evr, DcmElt((0x0002,0x0010),[ "1.2.840.10008.1.2" ]))
    end
    for el in d
        element_write(st, evr, el)
    end
end

end

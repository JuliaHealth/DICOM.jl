using DICOM

filename = tempname()*".zip"
dir = tempname()
mkpath(dir)

download("http://www.dclunie.com/images/pixelspacingtestimages.zip", filename)
run(`unzip $filename -d $dir`)
open(dcm_parse, joinpath(dir, "DISCIMG/IMAGES/MGIMAGEA"))

rm(filename)

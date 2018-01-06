using DICOM

dir = mktempdir()
filename = joinpath(dir,"dicomTestData.zip")

download("http://www.dclunie.com/images/pixelspacingtestimages.zip", filename)
run(`unzip $filename -d $dir`)
dcm_parse(joinpath(dir, "DISCIMG/IMAGES/MGIMAGEA"))

rm(filename)

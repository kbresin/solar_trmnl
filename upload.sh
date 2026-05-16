PATH=$PATH:/usr/local/bin
aws s3 cp --profile glcsolar_s3 "$1" s3://glcsolar/public/CE243659F38BF956/output.bmp

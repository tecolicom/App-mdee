# Hashed theme - append closing hashes to h3-h6
theme_cm+=(
    'h3=+;sub{s/(?<!#)$/ ###/r}'
    'h4=+;sub{s/(?<!#)$/ ####/r}'
    'h5=+;sub{s/(?<!#)$/ #####/r}'
    'h6=+;sub{s/(?<!#)$/ ######/r}'
)

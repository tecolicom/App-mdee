# Default theme - RoyalBlue base color
# Light mode: full definition
# Dark mode: differences only (inherits from light)

declare -gA theme_light=(
           [base]='<RoyalBlue>=y25'
        [comment]='${base}+r60'
           [bold]='${base}D'
         [strike]='X'
         [italic]='I'
           [link]="$link_func"
          [image]="$image_func"
     [image_link]="$image_link_func"
             [h1]='L25DE/${base}'
             [h2]='L25DE/${base}+y20'
             [h3]='L25DN/${base}+y30'
             [h4]='${base}UD'
             [h5]='${base}+y20;U'
             [h6]='${base}+y20'
     [code_mark]='L20'
     [code_info]='L18'
    [code_block]='/L23;E'
   [code_inline]='/L23'
)

declare -gA theme_dark=(
           [base]='<RoyalBlue>=y80'
             [h1]='L00DE/${base}'
             [h2]='L00DE/${base}-y15'
             [h3]='L00DN/${base}-y25'
             [h4]='${base}UD'
             [h5]='${base}-y20;U'
             [h6]='${base}-y20'
     [code_mark]='L10'
     [code_info]='L12'
    [code_block]='/L05;E'
   [code_inline]='/L05'
)

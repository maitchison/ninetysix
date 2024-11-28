unit graph

{ Graphics libray}

type Image = class

private
    width: int;
    height: int;

    pixels: array[256,256] of byte;

    constructor create();
    begin
    end;


{Used for drawing UI images.}
procedure splat(img: Image)
begin
end;
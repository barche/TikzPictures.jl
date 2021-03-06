module TikzPictures

export TikzPicture, PDF, TEX, TIKZ, SVG, save, tikzDeleteIntermediate, tikzCommand, TikzDocument, push!
import Base: push!
import LaTeXStrings: LaTeXString, @L_str, @L_mstr
export LaTeXString, @L_str, @L_mstr

_tikzDeleteIntermediate = true
_tikzCommand = "lualatex"

# standalone workaround:
# see http://tex.stackexchange.com/questions/315025/lualatex-texlive-2016-standalone-undefined-control-sequence
_standaloneWorkaround = false

function standaloneWorkaround()
    global _standaloneWorkaround
    _standaloneWorkaround
end

function standaloneWorkaround(value::Bool)
    global _standaloneWorkaround
    _standaloneWorkaround = value
    nothing
end

function tikzDeleteIntermediate(value::Bool)
    global _tikzDeleteIntermediate
    _tikzDeleteIntermediate = value
    nothing
end

function tikzDeleteIntermediate()
    global _tikzDeleteIntermediate
    _tikzDeleteIntermediate
end

function tikzCommand(value::AbstractString)
    global _tikzCommand
    _tikzCommand = value
    nothing
end

function tikzCommand()
    global _tikzCommand
    _tikzCommand
end

mutable struct TikzPicture
    data::AbstractString
    options::AbstractString
    preamble::AbstractString
    usePDF2SVG::Bool
    enableWrite18::Bool
    TikzPicture(data::AbstractString; options="", preamble="", usePDF2SVG=true, enableWrite18=true) = new(data, options, preamble, usePDF2SVG, enableWrite18)
end

mutable struct TikzDocument
    pictures::Vector{TikzPicture}
    captions::Vector{AbstractString}
end

TikzDocument() = TikzDocument(TikzPicture[], String[])

function push!(td::TikzDocument, tp::TikzPicture; caption="")
    push!(td.pictures, tp)
    push!(td.captions, caption)
end

function removeExtension(filename::AbstractString, extension::AbstractString)
    if endswith(filename, extension) || endswith(filename, uppercase(extension))
        return filename[1:(end - length(extension))]
    else
        return filename
    end
end

abstract type SaveType end

mutable struct PDF <: SaveType
    filename::AbstractString
    PDF(filename::AbstractString) = new(removeExtension(filename, ".pdf"))
end

mutable struct TEX <: SaveType
    filename::AbstractString
    include_preamble::Bool
    TEX(filename::AbstractString; include_preamble::Bool=true) = new(removeExtension(filename, ".tex"), include_preamble)
end

mutable struct TIKZ <: SaveType
    filename::AbstractString
    include_preamble::Bool
    TIKZ(filename::AbstractString) = new(removeExtension(filename, ".tikz"), false)
end

mutable struct SVG <: SaveType
    filename::AbstractString
    SVG(filename::AbstractString) = new(removeExtension(filename, ".svg"))
end

extension(f::SaveType) = lowercase(split("$(typeof(f))",".")[end])

showable(::MIME"image/svg+xml", tp::TikzPicture) = true

function save(f::Union{TEX,TIKZ}, tp::TikzPicture)
    filename = f.filename
    ext = extension(f)
    tex = open("$(filename).$(ext)", "w")
    if f.include_preamble
        if standaloneWorkaround()
            println(tex, "\\RequirePackage{luatex85}")
        end
        println(tex, "\\documentclass[tikz]{standalone}")
        println(tex, tp.preamble)
        println(tex, "\\begin{document}")
    end
    print(tex, "\\begin{tikzpicture}[")
    print(tex, tp.options)
    println(tex, "]")
    println(tex, tp.data)
    println(tex, "\\end{tikzpicture}")
    if f.include_preamble
        println(tex, "\\end{document}")
    end
    close(tex)
end

function save(f::TEX, td::TikzDocument)
    if isempty(td.pictures)
        error("TikzDocument does not contain pictures")
    end
    filename = f.filename
    tex = open("$(filename).tex", "w")
    if f.include_preamble
        println(tex, "\\documentclass{article}")
        println(tex, "\\usepackage{caption}")
        println(tex, "\\usepackage{tikz}")
        println(tex, td.pictures[1].preamble)
        println(tex, "\\begin{document}")
    end
    println(tex, "\\centering")
    @assert length(td.pictures) == length(td.captions)
    i = 1
    for tp in td.pictures
        println(tex, "\\centering")
        print(tex, "\\begin{tikzpicture}[")
        print(tex, tp.options)
        println(tex, "]")
        println(tex, tp.data)
        println(tex, "\\end{tikzpicture}")
        print(tex, "\\captionof{figure}{")
        print(tex, td.captions[i])
        println(tex, "}")
        println(tex, "\\vspace{5ex}")
        println(tex)
        i += 1
    end
    if f.include_preamble
        println(tex, "\\end{document}")
    end
    close(tex)
end

function latexerrormsg(s)
    beginError = false
    for l in split(s, '\n')
        if beginError
            if !isempty(l) && l[1] == '?'
                return
            else
                println(l)
            end
        else
            if !isempty(l) && l[1] == '!'
                println(l)
                beginError = true
            end
        end
    end
end

function save(f::PDF, tp::TikzPicture)
    foldername = dirname(f.filename)
    if isempty(foldername)
        foldername = "."
    end

    # latex command will only work if in the same directory as the .tex files
    # switching directories (temporarily) since the .tex files are in the tmp dir
    temp_dir = mktempdir(foldername)
    original_dir = abspath(".")
    cd(abspath(temp_dir))

    # Generate the .tex file and pass along any possible errors
    # This will throw an error if the directory doesn't exist
    save(TEX(f.filename * ".tex"), tp) # Save the tex file in the directory that was given

    # From the .tex file, generate a pdf within the specified folder
    latexCommand = ``
    if tp.enableWrite18
        latexCommand = `$(tikzCommand()) --enable-write18 --output-directory=. $(f.filename)`
    else
        latexCommand = `$(tikzCommand()) --output-directory=. $(f.filename)`
    end
    latexSuccess = success(latexCommand)

    # switch back to original directory
    cd(original_dir)

    tex_log = read(temp_dir * "/" * f.filename * ".log", String)

    if occursin("LaTeX Warning: Label(s)", tex_log)
        success(latexCommand)
    end

    try
        # Shouldn't need to be try-catched anymore, but best to be safe
        # This failing is NOT critical either, so just make it a warning
        if tikzDeleteIntermediate()
            target_file = temp_dir * "/" * "$(f.filename).pdf"
            if isfile(target_file)
                # Note: file may not exist if !latexSuccess
                # Moves pdf out of temp directory
                mv(target_file, foldername * "/" * "$(f.filename).pdf")
            end
            rm(temp_dir, recursive=true)
        end
    catch
        @warn "TikzPictures: Your intermediate files are not being deleted."
    end

    if !latexSuccess
        # Remove failed attempt.
        if !standaloneWorkaround() && occursin("\\sa@placebox ->\\newpage \\global \\pdfpagewidth", tex_log)
            standaloneWorkaround(true)
            save(f, tp)
            return
        end
        latexerrormsg(log)
        error("LaTeX error")
    end
end

function save(f::PDF, td::TikzDocument)
    foldername = dirname(f.filename)
    if isempty(foldername)
        foldername = "."
    end

    # lualatex command (tikzCommand()) will only work if in the same directory as the .tex files
    # switching directories (temporarily) since the .tex files are in the tmp dir
    temp_dir = mktempdir(foldername)
    original_dir = abspath(".")
    cd(abspath(temp_dir))

    try
        save(TEX(f.filename * ".tex"), td)
        if td.pictures[1].enableWrite18
            success(`$(tikzCommand()) --enable-write18 --output-directory=. $(f.filename)`)
        else
            success(`$(tikzCommand()) --output-directory=. $(f.filename)`)
        end

        # switch back to original directory
        cd(original_dir)
        if tikzDeleteIntermediate()
            # Moves pdf out of temp directory and removes temp directory
            mv(temp_dir * "/" * "$(f.filename).pdf", foldername * "/" * "$(f.filename).pdf")
            rm(temp_dir, recursive=true)
        end
    catch
        @warn "Error saving as PDF."
        rethrow()
    end
end


function save(f::SVG, tp::TikzPicture)
    try
        filename = f.filename
        folder = abspath(".")
        temp_dir = mktempdir(folder)
        original_dir = abspath(".")
        cd(abspath(temp_dir))
        if tp.usePDF2SVG
            save(PDF(filename), tp)
            cd(original_dir)
            success(`pdf2svg $(temp_dir * "/" * filename).pdf $filename.svg`) || error("pdf2svg failure")
            if tikzDeleteIntermediate()
                # delete tmp dir
                rm(temp_dir, recursive=true)
            end
        else
            save(TEX("$(filename).tex"), tp)
            if tp.enableWrite18
                success(`$(tikzCommand()) --enable-write18 --output-format=dvi .`)
            else
                success(`$(tikzCommand()) --output-format=dvi .`)
            end
            success(`dvisvgm --no-fonts $(filename)`)

            # switch back to original dir
            cd(original_dir)

            if tikzDeleteIntermediate()
                # move svg from tmp to current dir and delete tmp dir
                mv(temp_dir * "/" * "$(filename).svg", foldername * "/" * "$(filename).svg")
                rm(temp_dir, recursive=true)
            end
        end
    catch
        @warn "Error saving as SVG"
        rethrow()
    end
end

# this is needed to work with multiple images in ijulia (kind of a hack)
global _tikzid = round(UInt64, time() * 1e6)

function Base.show(f::IO, ::MIME"image/svg+xml", tp::TikzPicture)
    global _tikzid
    filename = "tikzpicture"
    save(SVG(filename), tp)
    s = read("$filename.svg", String)
    s = replace(s, "glyph" => "glyph-$(_tikzid)-")
    s = replace(s, "\"clip" => "\"clip-$(_tikzid)-")
    s = replace(s, "#clip" => "#clip-$(_tikzid)-")
    s = replace(s, "\"image" => "\"image-$(_tikzid)-")
    s = replace(s, "#image" => "#image-$(_tikzid)-")
    s = replace(s, "linearGradient id=\"linear" => "linearGradient id=\"linear-$(_tikzid)-")
    s = replace(s, "#linear" => "#linear-$(_tikzid)-")
    s = replace(s, "image id=\"" => "image style=\"image-rendering: pixelated;\" id=\"")
    _tikzid += 1
    println(f, s)
    if tikzDeleteIntermediate()
        rm("$filename.svg")
    end
end

end # module

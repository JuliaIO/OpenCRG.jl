using OpenCRG

function (@main)(args)
    data = read_crg(args[1])
    show(devnull, data)
    show(devnull, MIME"text/plain"(), data)
    u, v, x, y, z = road_surface_grid(data)
    for (i, j) in ((1, 1), (length(u) ÷ 2, length(v) ÷ 2), (length(u), length(v)))
        line = string(u[i], ' ', v[j], ' ', x[i,j], ' ', y[i,j], ' ', z[i,j])
        ccall(:puts, Cint, (Cstring,), line)
    end
    return 0
end

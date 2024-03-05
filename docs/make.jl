using K8sDeputy
using Documenter

pages = ["Home" => "index.md",
         "Health Checks" => "health_checks.md",
         "Graceful Termination" => "graceful_termination.md",
         "API" => "api.md"]

makedocs(; modules=[K8sDeputy],
         format=Documenter.HTML(; prettyurls=get(ENV, "CI", nothing) == "true"),
         sitename="K8sDeputy.jl",
         authors="Beacon Biosignals",
         pages)

deploydocs(; repo="github.com/beacon-biosignals/K8sDeputy.jl.git",
           push_preview=true,
           devbranch="main")

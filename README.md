![Logo](full_logo.png)
---

A `JuMP` extension for expressing and solving infinite-dimensional optimization
problems. Such areas include [stochastic programming](https://en.wikipedia.org/wiki/Stochastic_programming),
[dynamic programming](https://en.wikipedia.org/wiki/Dynamic_programming),
space-time optimization, and more. `InfiniteOpt` serves as an easy to use modeling
interface for these advanced problem types that can be used by those with little
to no background in these areas. It also it contains a wealth of capabilities
making it a powerful and convenient tool for advanced users.  

| **Documentation**                                                               | **Build Status**                                                                                |
|:-------------------------------------------------------------------------------:|:-----------------------------------------------------------------------------------------------:|
| [![](https://img.shields.io/badge/docs-stable-blue.svg)](https://pulsipher.github.io/InfiniteOpt.jl/stable) | [![Build Status](https://api.travis-ci.com/pulsipher/InfiniteOpt.jl.svg?branch=v0.1.1)](https://travis-ci.com/pulsipher/InfiniteOpt.jl) [![Build Status2](https://ci.appveyor.com/api/projects/status/p3srfp3uuvchfg3j/branch/v0.1.1?svg=true)](https://ci.appveyor.com/project/pulsipher/InfiniteOpt-jl) [![codecov.io](https://codecov.io/github/pulsipher/InfiniteOpt.jl/coverage.svg?branch=release_prep)](https://codecov.io/github/pulsipher/InfiniteOpt.jl?branch=release_prep) |
| [![](https://img.shields.io/badge/docs-dev-blue.svg)](https://pulsipher.github.io/InfiniteOpt.jl/dev) | [![Build Status](https://travis-ci.com/pulsipher/InfiniteOpt.jl.svg?branch=master)](https://travis-ci.com/pulsipher/InfiniteOpt.jl) [![Build Status2](https://ci.appveyor.com/api/projects/status/github/pulsipher/InfiniteOpt.jl?branch=master&svg=true)](https://ci.appveyor.com/project/pulsipher/InfiniteOpt-jl) [![codecov.io](https://codecov.io/github/pulsipher/InfiniteOpt.jl/coverage.svg?branch=master)](https://codecov.io/github/pulsipher/InfiniteOpt.jl?branch=master) |

Its capabilities include:
- `JuMP`-like symbolic macro interface
- Infinite set abstractions for parameterization of variables/constraints
- Finite parameters support and use (similar to `ParameterJuMP`)
- Direct support of infinite, point, and hold variables
- Symbolic measure (integral) expression
- Infinite/finite constraint definition
- Ordinary differential equation support (coming soon with `v0.2.0`)
- Automated model transcription/reformulation and solution
- Compatible with all [JuMP-supported solvers](https://www.juliaopt.org/JuMP.jl/dev/installation/#Getting-Solvers-1)
- Readily extendable to accommodate user defined abstractions and solution techniques.

Currently, the following infinite and finite problem types are accepted:
- Variables
    - Continuous and semi-continuous
    - Binary
    - Integer and semi-integer
- Objectives
    - Linear
    - Quadratic (convex and non-convex)
    - Higher-order powers (via place holder variables)
- Constraints
    - Linear
    - Quadratic (convex and non-convex)
    - Higher-order powers (via place holder variables)

Comments, suggestions and improvements are welcome and appreciated.

## License
`InfiniteOpt` is licensed under the [MIT "Expat" license](./LICENSE).

## Installation
`InfiniteOpt.jl` is a registered package and can be installed by entering the
following in the package manager.

```julia
(v1.4) pkg> add InfiniteOpt
```

## Documentation
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://pulsipher.github.io/InfiniteOpt.jl/stable)

Please visit our [documentation pages](https://pulsipher.github.io/InfiniteOpt.jl/stable) to learn more. These pages are quite extensive and feature overviews, guides, manuals,
tutorials, examples, and more!

## Project Status
The package is tested against Julia `1.0`, `1.1`, `1.2`, `1.3`, `1.4`, and nightly on Linux, macOS, and Windows.

## Contributing
`InfiniteOpt` is being actively developed and suggestions or other forms of contribution are encouraged.
There are many ways to contribute to this package. For more information please
visit [CONTRIBUTING](https://github.com/pulsipher/InfiniteOpt.jl/blob/master/CONTRIBUTING.md).

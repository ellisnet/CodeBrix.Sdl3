using Xunit;
using Xunit.Sdk;
using Xunit.v3;

// SDL keeps process-global state (SDL_Init/SDL_Quit, the error string, hints), so the suite runs
// serially.
[assembly: Parallelization(Mode = ParallelMode.None)]

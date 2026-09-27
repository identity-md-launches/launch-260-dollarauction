# Vendored dependencies

Dependencies are ordinary source files, never submodules. Production imports use the following unmodified subset of OpenZeppelin Contracts **v5.0.2**: ERC20, IERC20, IERC20Metadata, IERC20Permit, SafeERC20, IERC6093, Context, Address, and ReentrancyGuard. Its MIT license is included at `lib/openzeppelin-contracts/LICENSE`.

- Upstream: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2
- Download: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
- Downloaded archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`

Tests use the complete `src/` directory from forge-std **v1.9.7**. MIT and Apache license files are included under `lib/forge-std/`. These testing helpers are not part of application runtime bytecode.

- Upstream: https://github.com/foundry-rs/forge-std/tree/v1.9.7
- Download: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
- Downloaded archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Remappings are explicit in `remappings.txt`. Builds and tests require no downloads when Foundry and pinned solc 0.8.26 are present. ABI export uses Python 3's standard library. No compiler binaries are distributed in the repository.

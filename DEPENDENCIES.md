# Vendored dependencies

Sources and licences are included as ordinary files. No submodules, package install,
or network access is required to build or test with Foundry and Solidity 0.8.26 installed.

```text
openzeppelin-contracts v5.0.2
Source: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
Archive SHA-256: 18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a
Files: 6
```

```text
forge-std v1.9.7
Source: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
Archive SHA-256: 45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
Files: 30
```

OpenZeppelin includes only ERC20 and its transitive source imports. Forge Standard
Library includes its Solidity source tree for tests. Sources are unmodified;
SHA256SUMS in each dependency directory records their checksums relative to this
repository root. Licences are retained in each dependency directory.

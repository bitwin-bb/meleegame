# aquaria-backup
Roblox game project using a Nevermore-style Rojo layout.

## Getting Started
Install npm packages and Wally packages first:

```bash
pnpm install
wally install
```

Then start the Rojo server:

```bash
npm run serve
```

Source layout:

- `src/modules/Client` for UI and client-only services
- `src/modules/Server` for server-only services and tests
- `src/modules/Shared` for shared modules, classes, Cmdr definitions, and shared service modules
- `src/scripts` for the server/client boot scripts only

The authored Rojo tree now keeps `ReplicatedStorage` limited to `Packages`, while the Nevermore package root lives under `ServerScriptService/AquariaBackup`.

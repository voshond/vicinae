This package lets you extend the [Vicinae](https://docs.vicinae.com/) launcher using React and TypeScript.

[![Version](https://img.shields.io/npm/v/@vicinae/api.svg)](https://npmjs.org/package/@vicinae/api)
[![Downloads/week](https://img.shields.io/npm/dw/@vicinae/api.svg)](https://npmjs.org/package/@vicinae/api)

# Getting started

The recommend way to start developing a new extension is to [read the docs](https://docs.vicinae.com/extensions/introduction).

# Installation 

Install the package:

```
npm install @vicinae/api
```

# Versioning

The `@vicinae/api` package follows the same versioning as the main `vicinae` binary, since the API is always embedded in the binary.

# CLI usage

The package exports the `vici` binary which is used to build and run extensions in development mode.

While convenience scripts are already provided in the boilerplate, you can still call the binary manually:

```bash
npx vici --help

# assuming vicinae is running
npx vici develop

npx vici build -o my/output/path
```

# Task checkboxes

Commands with `rootSection: "tasks"` can replace their icon with a checkbox by calling `updateCommandMetadata({ checkbox: false })`. Use `true` for a checked task, or `null` to restore the icon. The state is held in memory, so the extension must publish it again after Vicinae restarts.

Clicking the checkbox launches that command with `launchContext.checkboxChecked` set to the requested new state. The extension handles the change and publishes the resulting state with `updateCommandMetadata`; Vicinae does not change it optimistically. Normal command activation is unchanged.

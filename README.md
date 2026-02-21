# Glimr Auth

The official authentication layer for the Glimr web framework, providing session-based auth and secure password hashing. This package is meant to be used alongside the `glimr-org/framework` package.

If you'd like to stay updated on Glimr's development, Follow [@migueljarias](https://x.com/migueljarias) on X (that's me) for updates.

## About

> **Note:** This repository contains the auth layer for Glimr. If you want to build an application using Glimr, visit the main [Glimr repository](https://github.com/glimr-org/glimr).

## Features

- **Session-Based Auth** - Login, logout, and identity checks backed by Glimr's session layer
- **Password Hashing** - Argon2id hashing with OWASP-recommended defaults
- **Timing-Safe** - Built-in dummy verify to prevent user enumeration via timing attacks
- **Session Fixation Protection** - Automatic session ID regeneration on login

## Installation

Add the auth layer to your Gleam project:

```sh
gleam add glimr_auth
```

## Learn More

- [Glimr](https://github.com/glimr-org/glimr) - Main Glimr repository
- [Glimr Framework](https://github.com/glimr-org/framework) - Core framework

### Built With

- [**argus**](https://hexdocs.pm/argus/) - Argon2 password hashing library for Gleam
- [**glimr**](https://hexdocs.pm/glimr/) - Core Glimr framework (sessions, config)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

The Glimr Auth layer is open-sourced software licensed under the [MIT](https://opensource.org/license/MIT) license.

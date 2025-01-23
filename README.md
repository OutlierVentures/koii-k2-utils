# Koii K2 Utilities

A collection of command line tools for working with the Koii K2 network.

## Monitoring

### validators-with-info.sh

An enhanced validator monitoring script that combines information from `koii validators` and `koii validator-info get` commands. It displays validator information including:
- Validator identity
- Skip rate
- Credits
- Validator names
- Website information (when available)

#### Usage

```bash
./monitoring/validators-with-info.sh [OPTIONS]

Options:
    -h          Show help message
    -s SORT     Sort validators by specified criteria (skiprate,credits)
    -d          Debug mode: save raw validator output to file
```

Example:
```bash
./monitoring/validators-with-info.sh -s skiprate,credits
```

## Requirements

- Bash shell environment
- [Koii CLI tools](https://www.koii.network/docs/run-a-node/k2-validators/system-setup#3-koii-cli-setup) installed and configured
  - `koii validators` command available
  - `koii validator-info` command available
- Standard Unix utilities:
  - `awk`
  - `sed`
  - `sort`
  - `grep`

## License

This project is licensed under the terms included in the [LICENSE](LICENSE) file.

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
    -s SORT     Sort validators by specified criteria. Multiple criteria can be
                comma-separated. Available options:
                  skiprate: Sort by skip rate (ascending)
                  credits:  Sort by credits (descending)
                Example: -s skiprate,credits
    -d          Debug mode: save raw validator output to file
```

Example:
```bash
./monitoring/validators-with-info.sh -s skiprate,credits
```

## Log Rotation

### log-rotate.sh

A script to safely rotate the `koii-rpc.log` file. Designed to be run weekly as a root cron job. It handles being run multiple times a day by creating suffixed archive files (e.g., `koii-rpc.20240101.log`, `koii-rpc.20240101-2.log`).

The script:
- Archives the current log file with a timestamp
- Creates a new empty log file with correct ownership
- Restarts the validator service to release the old file handle
- Trims the archived log to keep only the most recent lines (configurable)

#### Usage

```bash
sudo ./logrotate/log-rotate.sh
```

#### Configuration

The script loads configuration from a `.env` file if it exists in the `logrotate` directory. Copy `.env.example` to `.env` and modify as needed:

```bash
cp logrotate/.env.example logrotate/.env
```

Configuration options:
- `LOG_DIR` - Directory containing the log file (default: `/home/koii`)
- `LOG_FILE` - Name of the log file to rotate (default: `koii-rpc.log`)
- `SERVICE_NAME` - Systemd service name to restart (default: `koii-validator`)
- `LOG_USER` - User that should own the log file (default: `koii`)
- `LOG_GROUP` - Group that should own the log file (default: `koii`)
- `LINES_TO_KEEP` - Number of lines to keep in archived logs (default: `1000000`)

If no `.env` file exists, the script uses the default values above.

#### Cron Setup

To run automatically, add to root's crontab:

```bash
sudo crontab -e
```

Add a line to run weekly (e.g., every Sunday at 2 AM):

```
0 2 * * 0 /path/to/koii-k2-utils/logrotate/log-rotate.sh
```

## Requirements

- Bash shell environment
- [Koii CLI tools](https://www.koii.network/docs/run-a-node/k2-validators/system-setup#3-koii-cli-setup) installed and configured
  - `koii validators` command available (for monitoring scripts)
  - `koii validator-info` command available (for monitoring scripts)
- Standard Unix utilities:
  - `awk`
  - `sed`
  - `sort`
  - `grep`
- For log rotation:
  - Root or sudo access (required for log rotation script)
  - Systemd service management (for restarting the validator service)

## Testing

This project uses [BATS](https://github.com/bats-core/bats-core) for testing. To run the tests, you'll need:

1. **BATS** - Install following the [official installation instructions](https://bats-core.readthedocs.io/en/stable/installation.html)

2. **bats-support and bats-assert** - These helper libraries must be installed and available. The test runner will automatically detect them if installed via npm or system-wide.

To run tests:
```bash
./run-tests.sh                                    # Run all tests (unit tests only)
./run-tests.sh tests/log-rotate.bats              # Run specific test file
./run-tests.sh tests/validators-with-info.bats    # Run unit tests only
./run-tests.sh tests/validators-with-info-integration.bats  # Run integration tests (requires koii CLI and network)
```

**Note:** Integration tests require the `koii` CLI tool and network connectivity. They will be skipped automatically if `koii` is not available. To skip integration tests, simply don't run the integration test file.

## License

This project is licensed under the terms included in the [LICENSE](LICENSE) file.

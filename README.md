# Github Action: Check Package Marker

This is a Github action that checks the build marker of archlinux/archlinuxarm/msys2 packages to confirm whether the current commit has already been built.

## Intended Workflow
This action is mainly for building a PKGBUILD package only when there is an update, to prevent repeated builds.

## How to Use

As with any Github Action, you must include it in a workflow for your repo to run. Place the workflow at `.github/workflows/main.yaml` in the default repo branch (required for scheduled jobs at this time). For more help, see [Github Actions documentation](https://docs.github.com/en/actions).

### Input Variables

**arch**:			- The CPU architecture that runs this package, sunch as: armv7, aarch64, x86_64;  
**repo**:           - The repository that this PKGBUILD package belongs to.  
**target_os**: 		- The operating system that this package uses; for archlinux/archlinuxarm, set this variable to 'Linux'; for Msys2, set this variable to 'Msys'.  
**marker_path**:	- The rclone path of the build tag file, such as: onedrive:/mirror/archlinux/build.marker  
**rclone_config**:  - The content of the rclone configuration file.  
**update**:         - Whether to update the remote build marker with the current commit hash.  
**github_token**:	- Token for accessing the remote repo with authentication  

### Output Variables

**marked**          - true if the current commit has already been built  
**last_hash**       - The commit hash of the last time the package was built  
**now_hash**        - The commit hash of this time the package is built.  
**error_message**   - If an error occurs, output the related error message.  

## Sample Workflow
This workflow is currently in use in some of my PKGBUILD repos.

```yaml
on:
  schedule:
    - cron:  '0 7 * * 1,4'
    # scheduled at 07:00 every Monday and Thursday

  workflow_dispatch:  # click the button on Github repo!


jobs:
  sync_with_upstream:
    runs-on: ubuntu-latest
    name: check package marker

    steps:
    # Step 1: run a standard checkout action, provided by github
    - name: Checkout main
      uses: actions/checkout@v3.5.2
      with:
        ref: main
        # submodules: 'recursive'

    # Step 2: run this check action
    - name: Check Package Marker
      id: mark
      uses: atomlong/Check-Marker-action@master
      with:
	    arch: armv7
        target_os: Linux
        marker_url: ""
        github_token: ${{ secrets.GITHUB_TOKEN }}   # optional, for accessing repos that require authentication

    # Step 3: Display a message if 'sync' step had new commits (simple test)
    - name: Check for new commits
      if: steps.mark.outputs.marked
      run: echo "No need to build the package for the current commit reversion."

    # Step 4: Print a helpful timestamp for your records (not required, just nice)
    - name: Timestamp
      run: date
```

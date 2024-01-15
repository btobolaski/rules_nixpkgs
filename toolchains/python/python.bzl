"""<!-- Edit the docstring in `toolchains/python/python.bzl` and run `bazel run //docs:update-README.md` to change this repository's `README.md`. -->

Rules to import Python toolchains and packages from Nixpkgs.

# Rules

* [nixpkgs_python_configure](#nixpkgs_python_configure)
* [nixpkgs_python_repository](#nixpkgs_python_repository)
"""

load(
    "@rules_nixpkgs_core//:nixpkgs.bzl",
    "nixpkgs_package",
)
load(
    "@rules_nixpkgs_core//:util.bzl",
    "is_bazel_version_at_least",
    "ensure_constraints",
    "label_string",
)

def _nixpkgs_python_toolchain_impl(repository_ctx):
    exec_constraints, target_constraints = ensure_constraints(repository_ctx)

    python2_runtime = ""
    if repository_ctx.attr.python2_repo:
        python2_runtime = repository_ctx.attr.python2_repo + ":runtime"

    python3_runtime = ""
    if repository_ctx.attr.python3_repo:
        python3_runtime = repository_ctx.attr.python3_repo + ":runtime"

    repository_ctx.file("BUILD.bazel", executable = False, content = """
load("@bazel_tools//tools/python:toolchain.bzl", "py_runtime_pair")
py_runtime_pair(
    name = "py_runtime_pair",
    py2_runtime = {python2_runtime},
    py3_runtime = {python3_runtime},
)
toolchain(
    name = "toolchain",
    toolchain = ":py_runtime_pair",
    toolchain_type = "@bazel_tools//tools/python:toolchain_type",
    exec_compatible_with = {exec_constraints},
    target_compatible_with = {target_constraints},
)
""".format(
        python2_runtime = label_string(python2_runtime),
        python3_runtime = label_string(python3_runtime),
        exec_constraints = exec_constraints,
        target_constraints = target_constraints,
    ))

    python_repo = repository_ctx.attr.python3_repo
    if not python_repo:
        python_repo = repository_ctx.attr.python2_repo

    repository_ctx.file("defs.bzl", executable = False, content = """
# Generated by rules_nixpkgs/toolchains/python/python.bzl
interpreter = "{}"
    """.format(python_repo + ":bin/python"))

_nixpkgs_python_toolchain = repository_rule(
    _nixpkgs_python_toolchain_impl,
    attrs = {
        # Using attr.string instead of attr.label, so that the repository rule
        # does not explicitly depend on the nixpkgs_package instances. This is
        # necessary, so that builds don't fail on platforms without nixpkgs.
        "python2_repo": attr.string(),
        "python3_repo": attr.string(),
        "exec_constraints": attr.string_list(),
        "target_constraints": attr.string_list(),
    },
)

def _python_nix_file_content(attribute_path, bin_path, version):
    bazel_version_match, bazel_from_source = is_bazel_version_at_least("4.2.0")
    add_shebang = bazel_version_match or bazel_from_source

    return """
with import <nixpkgs> {{ config = {{}}; overlays = []; }};
let
  addShebang = {add_shebang};
  interpreterPath = "${{{attribute_path}}}/{bin_path}";
  shebangLine = interpreter: writers.makeScriptWriter {{ inherit interpreter; }} "shebang" "";
in
runCommand "bazel-nixpkgs-python-toolchain"
  {{ executable = false;
    # Pointless to do this on a remote machine.
    preferLocalBuild = true;
    allowSubstitutes = false;
  }}
  ''
    n=$out/BUILD.bazel
    mkdir -p "$(dirname "$n")/bin"
    ln -s ${{interpreterPath}} $out/bin/python

    cat >>$n <<EOF
    py_runtime(
        name = "runtime",
        interpreter_path = "${{interpreterPath}}",
        python_version = "{version}",
        ${{lib.optionalString addShebang ''
          stub_shebang = "$(cat ${{shebangLine interpreterPath}})",
        ''}}
        visibility = ["//visibility:public"],
    )
    exports_files(["bin/python"])
    EOF
  ''
""".format(
        add_shebang = "true" if add_shebang else "false",
        attribute_path = attribute_path,
        bin_path = bin_path,
        version = version,
    )

def nixpkgs_python_configure(
        name = "nixpkgs_python_toolchain",
        python2_attribute_path = None,
        python2_bin_path = "bin/python",
        python3_attribute_path = "python3",
        python3_bin_path = "bin/python",
        repository = None,
        repositories = {},
        nix_file_deps = None,
        nixopts = [],
        fail_not_supported = True,
        quiet = False,
        exec_constraints = None,
        target_constraints = None,
        register = True):
    """Define and register a Python toolchain provided by nixpkgs.

    Creates `nixpkgs_package`s for Python 2 or 3 `py_runtime` instances and a
    corresponding `py_runtime_pair` and `toolchain`. The toolchain is
    automatically registered and uses the constraint:

    ```
    "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix"
    ```

    Args:
      name: The name-prefix for the created external repositories.
      python2_attribute_path: The nixpkgs attribute path for python2.
      python2_bin_path: The path to the interpreter within the package.
      python3_attribute_path: The nixpkgs attribute path for python3.
      python3_bin_path: The path to the interpreter within the package.
      repository: See [`nixpkgs_package`](#nixpkgs_package-repository).
      repositories: See [`nixpkgs_package`](#nixpkgs_package-repositories).
      nix_file_deps: See [`nixpkgs_package`](#nixpkgs_package-nix_file_deps).
      nixopts: See [`nixpkgs_package`](#nixpkgs_package-nixopts).
      fail_not_supported: See [`nixpkgs_package`](#nixpkgs_package-fail_not_supported).
      quiet: See [`nixpkgs_package`](#nixpkgs_package-quiet).
      exec_constraints: Constraints for the execution platform.
      target_constraints: Constraints for the target platform.
    """
    python2_specified = python2_attribute_path and python2_bin_path
    python3_specified = python3_attribute_path and python3_bin_path
    if not python2_specified and not python3_specified:
        fail("At least one of python2 or python3 has to be specified.")
    kwargs = dict(
        repository = repository,
        repositories = repositories,
        nix_file_deps = nix_file_deps,
        nixopts = nixopts,
        fail_not_supported = fail_not_supported,
        quiet = quiet,
    )
    python2_repo = None
    if python2_attribute_path:
        python2_repo = "@%s_python2//" % name
        nixpkgs_package(
            name = name + "_python2",
            nix_file_content = _python_nix_file_content(
                attribute_path = python2_attribute_path,
                bin_path = python2_bin_path,
                version = "PY2",
            ),
            **kwargs
        )
    python3_repo = None
    if python3_attribute_path:
        python3_repo = "@%s_python3//" % name
        nixpkgs_package(
            name = name + "_python3",
            nix_file_content = _python_nix_file_content(
                attribute_path = python3_attribute_path,
                bin_path = python3_bin_path,
                version = "PY3",
            ),
            **kwargs
        )
    _nixpkgs_python_toolchain(
        name = name,
        python2_repo = python2_repo,
        python3_repo = python3_repo,
        exec_constraints = exec_constraints,
        target_constraints = target_constraints,
    )

    if register:
        native.register_toolchains("@{}//:toolchain".format(name))


def _nixpkgs_python_repository_impl(repository_ctx):
    # Read generated json
    python_packages = repository_ctx.read(repository_ctx.path(repository_ctx.attr.json_deps))

    # Generate BUILD.bazel content from the json data
    content = 'load("@rules_nixpkgs_python//:python_package.bzl", "python_package");'
    for pkg_info in json.decode(python_packages):
        pkg_name = pkg_info["name"]
        pkg_store_path = pkg_info["store_path"]
        deps = pkg_info["deps"]
        pkg_link_path = "{}-link".format(pkg_name)
        repository_ctx.symlink(pkg_store_path, pkg_link_path)

        # Bazel chokes on files containing whitespaces, so we exclude them from
        # the glob, hoping they are not important
        content += """
python_package(
    name = "{name}",
    store_path = "{link}",
    files = glob(["{link}/**"], exclude=["{link}/**/* *"]),
    deps = {deps},
    visibility = ["//visibility:public"],
)
        """.format(name=pkg_name, link=pkg_link_path, deps=deps)

    # Write the content to the file
    repository_ctx.file("BUILD.bazel", content)

    # Generate //:requirements.bzl to provide `requirement` like rules_python
    repository_ctx.file("requirements.bzl", """
def requirement(package_name):
    return "@{}//:{{}}".format(package_name)
""".format(repository_ctx.attr.unmangled_name),
    )

    # TODO: make it lazy in the packages themselves ?


_nixpkgs_python_repository = repository_rule(
    _nixpkgs_python_repository_impl,
    attrs = {
        "json_deps": attr.label(),
        "unmangled_name": attr.string(),
    },
)


def nixpkgs_python_repository(
        name,
        repository = None,
        repositories = {},
        nix_file = None,
        nix_file_deps = [],
        quiet = False,
        ):
    """Define a collection of python packages based on a nix file.

    The only entry point is a [`nix_file`](#nixpkgs_python_repository-nix_file)
    which should expose a `pkgs` and a `python` attributes. `python` is the
    python interpreter, and `pkgs` a set of python packages that will be made
    available to bazel.

    :warning: All the packages in `pkgs` are built by this rule. It is
    therefore not a good idea to expose something as big as `pkgs.python3` as
    provided by nixpkgs.

    This rule is instead intended to expose an ad-hoc set of packages for your
    project, as can be built by poetry2nix, mach-nix, dream2nix or by manually
    picking the python packages you need from nixpkgs.

    The format is generic to support the many ways to generate such packages
    sets with nixpkgs. See our python [`tests`](/testing/toolchains/python) and
    [`examples`](/examples/toolchains/python) to get started.

    This rule is intended to mimic as closely as possible the [rules_python
    API](https://github.com/bazelbuild/rules_python#using-the-package-installation-rules).
    `nixpkgs_python_repository` should be a drop-in replacement of `pip_parse`.
    As such, it also provides a `requirement` function.

    :warning: Using the `requirement` fucntion inherits the same advantages and
    limitations as the one in rules_python. All the function does is create a
    label of the form `@{nixpkgs_python_repository_name}//:{package_name}`.
    While depending on such a label directly will work, the layout may change
    in the future. To be on the safe side, define and import your own
    `requirement` function if you need to play with these labels.

    :warning: Just as with rules_python, nothing is done to enforce consistency
    between the version of python used to generate this repository and the one
    configured in your toolchain, even if you use nixpkgs_python_toolchain. You
    should ensure they both use the same python from the same nixpkgs version.

    :warning: packages names exposed by this rule are determined by the `pname`
    attribute of the corresponding nix package. These may vary slightly from
    names used by rules_python. Should this be a problem, you can provide you
    own `requirement` function, for example one that lowercases its argument.

    Args:
      name: The name for the created package set.
      repository: See [`nixpkgs_package`](#nixpkgs_package-repository).
      repositories: See [`nixpkgs_package`](#nixpkgs_package-repositories).
      nix_file: See [`nixpkgs_package`](#nixpkgs_package-nix_file).
      nix_file_deps: See [`nixpkgs_package`](#nixpkgs_package-nix_file_deps).
      quiet: See [`nixpkgs_package`](#nixpkgs_package-quiet).
    """

    generated_deps_name = "generated_{}_deps".format(name)

    nixpkgs_package(
        name = generated_deps_name,
        nix_file = "@rules_nixpkgs_python//:package_set_to_json.nix",
        repository = repository,
        repositories = repositories,
        nix_file_deps = nix_file_deps + [ nix_file ],
        build_file_content = """exports_files(["requirements.json"])""",
        nixopts = [ "--arg", "nix_file", "$(location {})".format(nix_file) ],
        quiet = quiet,
    )

    _nixpkgs_python_repository(
        name = name,
        unmangled_name = name,
        json_deps = "@{}//:requirements.json".format(generated_deps_name),
    )




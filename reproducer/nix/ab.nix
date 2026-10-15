# The two stacks of the reproducer.
#
# AFTER  = nix-ros-overlay rolling as pinned in flake.lock. It has rmw_fastrtps_cpp 9.5.2-1, which has
#          the rosidl::Buffer support of ros2/rmw_fastrtps#867.
# BEFORE = the same scope with every package that carries rosidl::Buffer or #867 replaced by the last
#          release that does not: rosidl 5.1.3-1, rosidl_typesupport_fastrtps 3.9.3-1, rosidl_generator_py
#          0.27.0-1 and rmw_fastrtps 9.4.5-1. Every rosidl-buffer package is removed from every input list.
#          BEFORE is not a released stack. It is the stack the same distribution had before the feature.
# AFTER-FIXED = AFTER plus patches/rmw-fastrtps-*-forget-removed-subscriber.patch.
#
# BEFORE needs one backport. rmw_fastrtps#875 (TypeObject collection header flags) landed in 9.4.6 together
# with #867. Without it, a 9.4.5 endpoint never matches a 9.5.x endpoint for any message with a sequence field.
# The backport touches only rmw_fastrtps_shared_cpp/src/TypeSupport_impl.cpp, not the publish path.
{ pkgs, rosPackages }:
let
  lib = pkgs.lib;
  isBuf = p: lib.hasInfix "rosidl-buffer" (p.pname or p.name or "");
  dropBuf = ps: lib.filter (p: !(isBuf p)) ps;
  dropAll = old: {
    buildInputs = dropBuf (old.buildInputs or [ ]);
    propagatedBuildInputs = dropBuf (old.propagatedBuildInputs or [ ]);
    nativeBuildInputs = dropBuf (old.nativeBuildInputs or [ ]);
    checkInputs = dropBuf (old.checkInputs or [ ]);
  };
  rel = repo: pkg: ver: hash: pkgs.fetchurl {
    url = "https://github.com/ros2-gbp/${repo}/archive/release/rolling/${pkg}/${ver}.tar.gz";
    name = "${ver}.tar.gz";
    sha256 = hash;
  };
  swap = repo: pkg: ver: hash: old: (dropAll old) // {
    version = "${ver}-before";
    patches = lib.optional (pkg == "rmw_fastrtps_shared_cpp")
      ../patches/rmw-fastrtps-shared-cpp-9.4.5-collection-flag-backport.patch;
    src = rel repo pkg ver hash;
  };
  r = pkg: hash: swap "rosidl-release" pkg "5.1.3-1" hash;
  # The proxy package rmw-implementation is built against every RMW of the distribution. Only
  # rmw_fastrtps_cpp is needed, so the other RMWs stay out of the closure.
  notNeeded = [
    "ros-rolling-rmw-connextdds"
    "ros-rolling-rmw-cyclonedds-cpp"
    "ros-rolling-rmw-zenoh-cpp"
    "ros-rolling-rmw-fastrtps-dynamic-cpp"
  ];
  narrow = final: prev: {
    rmw-implementation = prev.rmw-implementation.overrideAttrs (old: {
      buildInputs = lib.filter (p: !(builtins.elem (p.pname or "") notNeeded)) old.buildInputs;
    });
  };
  withProbe = scope: (scope.overrideScope narrow).overrideScope (final: prev: {
    probe = final.callPackage ./probe.nix { };
  });
  after = withProbe rosPackages;
  before = ((rosPackages.overrideScope (final: prev: {
    rosidl-adapter = prev.rosidl-adapter.overrideAttrs (r "rosidl_adapter" "0jmpmj8gqhklnnfrk2zqkws0if23h39a68l9i5bmgvn9i0rqh36p");
    rosidl-cli = prev.rosidl-cli.overrideAttrs (r "rosidl_cli" "09r72xhlvyvg2cxy1k54azx3qd2k64fal9ij44vs4ml9llcrs4k9");
    rosidl-cmake = prev.rosidl-cmake.overrideAttrs (r "rosidl_cmake" "079czi0liqqi1pzdj6bfwa0762fafmb40xyi7hic1b73w3cfb9cb");
    rosidl-generator-c = prev.rosidl-generator-c.overrideAttrs (r "rosidl_generator_c" "10cck54cnmki30jgw1rb2glkib3xqdhblakzir0z9q9prrzjr75p");
    rosidl-generator-cpp = prev.rosidl-generator-cpp.overrideAttrs (r "rosidl_generator_cpp" "19q3x2zbas1rlkg9dn5b9281p32a89afg3pkpz627n7x8ky77qlf");
    rosidl-generator-type-description = prev.rosidl-generator-type-description.overrideAttrs (r "rosidl_generator_type_description" "14qzpknkq6fnmkm276lnfq1x68pnrvar6wmx7pcffvk2qlgiaiz2");
    rosidl-parser = prev.rosidl-parser.overrideAttrs (r "rosidl_parser" "18i4n696zybk8zwjg6mvv2cxsdhdyh8fy429r9rfasjsb8cg0syg");
    rosidl-pycommon = prev.rosidl-pycommon.overrideAttrs (r "rosidl_pycommon" "1kcvwranzq25lbr6d1v8l30an4dkk5c2z1dd9aymic06j900y2zh");
    rosidl-runtime-c = prev.rosidl-runtime-c.overrideAttrs (r "rosidl_runtime_c" "00syzrw0zk46c446ipkjr87wb1qlrmly52vb8aqgpm1wjmgkm77y");
    rosidl-runtime-cpp = prev.rosidl-runtime-cpp.overrideAttrs (r "rosidl_runtime_cpp" "0ibcshzz4pwja1s5v0yly8x6kn3wkjd6njll6m9bkcdb4kkhjxvd");
    rosidl-typesupport-interface = prev.rosidl-typesupport-interface.overrideAttrs (r "rosidl_typesupport_interface" "0pqlpyiwcivb4242kfq4gdac564xly4di77d1l4j5wwkc6knivq3");
    rosidl-typesupport-introspection-c = prev.rosidl-typesupport-introspection-c.overrideAttrs (r "rosidl_typesupport_introspection_c" "1xnnljfr83m591gym7xsxjf8cnpvpa2r0mr6x4gc9wssiynibnx6");
    rosidl-typesupport-introspection-cpp = prev.rosidl-typesupport-introspection-cpp.overrideAttrs (r "rosidl_typesupport_introspection_cpp" "14iaxp0jqchx8syn795ygbgcfy6ch42diz0k4b9pbg5mjsnmif34");
    rosidl-typesupport-fastrtps-c = prev.rosidl-typesupport-fastrtps-c.overrideAttrs (swap "rosidl_typesupport_fastrtps-release" "rosidl_typesupport_fastrtps_c" "3.9.3-1" "1hsrpamfryrl6j0r2km077snfy1s11a6ims243ka1fw4q9a8vxz7");
    rosidl-typesupport-fastrtps-cpp = prev.rosidl-typesupport-fastrtps-cpp.overrideAttrs (swap "rosidl_typesupport_fastrtps-release" "rosidl_typesupport_fastrtps_cpp" "3.9.3-1" "0az08psjv9xksxaw3mppvvn27q1zrgv9gcik8dhnm3h485kfvs6m");
    rmw-fastrtps-cpp = prev.rmw-fastrtps-cpp.overrideAttrs (swap "rmw_fastrtps-release" "rmw_fastrtps_cpp" "9.4.5-1" "1akcjq6i6s7wpfi505x8ksaxvp08jr31k06smh82r1ir5k58sngk");
    rmw-fastrtps-shared-cpp = prev.rmw-fastrtps-shared-cpp.overrideAttrs (swap "rmw_fastrtps-release" "rmw_fastrtps_shared_cpp" "9.4.5-1" "0m72l6gx6vbj5q6n6czm8gkrsys91ynfrs6ddqiha381h6sb29h1");
    # packages that only list a rosidl-buffer package as an input
    rosidl-core-runtime = prev.rosidl-core-runtime.overrideAttrs dropAll;
    rosidl-generator-py = prev.rosidl-generator-py.overrideAttrs (swap "rosidl_python-release" "rosidl_generator_py" "0.27.0-1" "1a711l64damkazhxiy198l5vah776zv6qxapqh58dvvwqbzwh3ii");
    rosidl-runtime-py = prev.rosidl-runtime-py.overrideAttrs dropAll;
  })).overrideScope narrow).overrideScope (final: prev: {
    probe = final.callPackage ./probe.nix { };
  });
  fixed = after.overrideScope (final: prev: {
    rmw-fastrtps-cpp = prev.rmw-fastrtps-cpp.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/rmw-fastrtps-cpp-forget-removed-subscriber.patch ];
    });
    rmw-fastrtps-shared-cpp = prev.rmw-fastrtps-shared-cpp.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/rmw-fastrtps-shared-cpp-forget-removed-subscriber.patch ];
    });
  });
  # Prints one line per publish decision of a buffer-aware publisher: the live subscription count, the
  # sizes of the three lists and the branch taken.
  withDebug = scope: scope.overrideScope (final: prev: {
    rmw-fastrtps-cpp = prev.rmw-fastrtps-cpp.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/debug-print-publish-decision.patch ];
    });
  });
in
{
  after = after.probe;
  after-fixed = fixed.probe;
  before = before.probe;
  after-debug = (withDebug after).probe;
  after-fixed-debug = (withDebug fixed).probe;
}

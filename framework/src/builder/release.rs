// Copyright © Aptos Foundation
// SPDX-License-Identifier: Apache-2.0

#![forbid(unsafe_code)]

use diem_framework::{
    docgen::DocgenOptions, BuildOptions, ReleaseBundle, ReleaseOptions, RELEASE_BUNDLE_EXTENSION,
};

use std::{fmt::Display, path::PathBuf, str::FromStr};

use crate::BYTECODE_VERSION;

use super::named_addresses::NAMED_ADDRESSES;

// BuilderOptions Helper

/// The default build profile for the compiled move
/// framework bytecode (.mrb file)
pub fn ol_release_default() -> BuildOptions {
    BuildOptions {
        dev: false,
        with_srcs: true,
        with_abis: true,
        with_source_maps: true,
        with_error_map: true,
        named_addresses: NAMED_ADDRESSES.to_owned(),
        install_dir: None,
        with_docs: false,
        docgen_options: None,
        skip_fetch_latest_git_deps: true,
        bytecode_version: Some(BYTECODE_VERSION),
    }
}

// ===============================================================================================
// Release Targets

/// Represents the available release targets. `Current` is in sync with the current client branch,
/// which is ensured by tests.
#[derive(clap::ValueEnum, Clone, Copy, Debug)]
pub enum ReleaseTarget {
    Head,
    Devnet,
    Testnet,
    Mainnet,
}

impl Display for ReleaseTarget {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let str = match self {
            ReleaseTarget::Head => "head",
            ReleaseTarget::Devnet => "devnet",
            ReleaseTarget::Testnet => "testnet",
            ReleaseTarget::Mainnet => "mainnet",
        };
        write!(f, "{}", str)
    }
}

impl FromStr for ReleaseTarget {
    type Err = &'static str;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "head" => Ok(ReleaseTarget::Head),
            "devnet" => Ok(ReleaseTarget::Devnet),
            "testnet" => Ok(ReleaseTarget::Testnet),
            "mainnet" => Ok(ReleaseTarget::Mainnet),
            _ => Err("Invalid target. Valid values are: head, devnet, testnet, mainnet"),
        }
    }
}

impl ReleaseTarget {
    /// Returns the package directories (relative to `framework`), in the order
    /// they need to be published, as well as an optional path to the file where
    /// rust bindings generated from the package should be stored.
    pub fn packages(self) -> Vec<(&'static str, Option<&'static str>)> {
        let result = vec![
            ("move-stdlib", None),
            ("vendor-stdlib", None),
            (
                "libra-framework",
                Some("cached-packages/src/libra_framework_sdk_builder.rs"),
            ),
        ];
        result
    }

    /// Returns the file name under which this particular target's release buundle is stored.
    /// For example, for `Head` the file name will be `head.mrb`.
    pub fn file_name(self) -> String {
        format!("{}.{}", self, RELEASE_BUNDLE_EXTENSION)
    }

    /// Loads the release bundle for this particular target.
    pub fn load_bundle(self) -> anyhow::Result<ReleaseBundle> {
        //////// 0L ////////
        let this_path = PathBuf::from_str(env!("CARGO_MANIFEST_DIR"))?;
        let path = this_path.join("releases").join(self.file_name());
        ReleaseBundle::read(path)
    }

    pub fn create_release_options(self, _with_srcs: bool, out: Option<PathBuf>) -> ReleaseOptions {
        let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        // let crate_dir = crate_dir.parent().unwrap().to_path_buf();
        let packages = self
            .packages()
            .into_iter()
            .map(|(path, binding_path)| {
                (crate_dir.join(path), binding_path.unwrap_or("").to_owned())
            })
            .collect::<Vec<_>>();
        ReleaseOptions {
            build_options: BuildOptions {
                with_docs: true,
                docgen_options: Some(DocgenOptions {
                    include_impl: true,
                    include_specs: true,
                    specs_inlined: false,
                    include_dep_diagram: false,
                    collapsed_sections: true,
                    landing_page_template: Some("doc_template/overview.md".to_string()),
                    references_file: Some("doc_template/references.md".to_string()),
                }),
                ..ol_release_default()
            },
            packages: packages.iter().map(|(path, _)| path.to_owned()).collect(),
            rust_bindings: packages
                .into_iter()
                .map(|(_, binding)| {
                    if !binding.is_empty() {
                        crate_dir.join(binding).display().to_string()
                    } else {
                        binding
                    }
                })
                .collect(),
            output: if let Some(path) = out {
                path
            } else {
                // Place in release directory //////// 0L ////////
                crate_dir.join("releases/head.mrb")
            },
        }
    }

    pub fn create_release(self, with_srcs: bool, out: Option<PathBuf>) -> anyhow::Result<()> {
        let options = self.create_release_options(with_srcs, out);
        #[cfg(unix)]
        {
            options.create_release()
        }
        #[cfg(windows)]
        {
            // Windows requires to set the stack because the package compiler puts too much on the
            // stack for the default size.  A quick internet search has shown the new thread with
            // a custom stack size is the easiest course of action.
            const STACK_SIZE: usize = 4 * 1024 * 1024;
            let child_thread = std::thread::Builder::new()
                .name("Framework-release".to_string())
                .stack_size(STACK_SIZE)
                .spawn(|| options.create_release())
                .expect("Expected to spawn release thread");
            child_thread
                .join()
                .expect("Expected to join release thread")
        }
    }
}
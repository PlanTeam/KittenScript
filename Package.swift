import PackageDescription

let package = Package(
    name: "KittenScript",
    targets: [
        Target(name: "KittenScript"),
        Target(name: "KittenScriptExample", dependencies: ["KittenScript"]),
    ],
    exclude: ["Scripts"]
)

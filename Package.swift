import PackageDescription

let package = Package(
    name: "KittenScript",
    dependencies: [
        .Package(url: "https://github.com/OpenKitten/CommonKitten.git", majorVersion: 0)
    ],
    exclude: ["Scripts"]
)

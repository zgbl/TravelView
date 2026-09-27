import { readdirSync } from "node:fs";
import { basename, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const bucket = process.env.R2_BUCKET_NAME || "travelview-private-flags";
const flagDirectory = resolve("node_modules/flag-icons/flags/4x3");
const fallbackFlag = resolve("assets/flags/XX.svg");
const wrangler = resolve("node_modules/.bin/wrangler");
const files = readdirSync(flagDirectory)
  .filter((file) => file.endsWith(".svg"))
  .sort()
  .map((file) => ({
    country: basename(file, ".svg").toUpperCase(),
    path: resolve(flagDirectory, file),
  }));

files.push({ country: "XX", path: fallbackFlag });

console.log(
  "Uploading " +
    files.length +
    " private SVG flag objects to R2 bucket " +
    bucket,
);

for (const file of files) {
  const result = spawnSync(
    wrangler,
    [
      "r2",
      "object",
      "put",
      bucket + "/flags/" + file.country + ".svg",
      "--file",
      file.path,
      "--content-type",
      "image/svg+xml",
      "--remote",
    ],
    { stdio: "inherit" },
  );

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error("Wrangler upload failed for " + file.country);
  }
}

console.log("Uploaded " + files.length + " flag objects.");

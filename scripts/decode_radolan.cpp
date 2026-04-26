#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <regex>
#include <string>
#include <tuple>
#include <vector>

namespace fs = std::filesystem;

struct Grid {
    int width = 0;
    int height = 0;
};

static bool readFile(const fs::path &p, std::vector<uint8_t> &out) {
    std::ifstream f(p, std::ios::binary);
    if (!f) return false;
    f.seekg(0, std::ios::end);
    const auto size = f.tellg();
    if (size <= 0) return false;
    f.seekg(0, std::ios::beg);
    out.resize(static_cast<size_t>(size));
    f.read(reinterpret_cast<char *>(out.data()), static_cast<std::streamsize>(out.size()));
    return f.good() || f.eof();
}

static bool parseGrid(const std::string &header, Grid &g) {
    std::smatch m;
    static const std::regex reBG("BG([0-9]{4})([0-9]{4})");
    if (std::regex_search(header, m, reBG)) {
        g.height = std::stoi(m[1].str());
        g.width = std::stoi(m[2].str());
        return g.width > 0 && g.height > 0;
    }

    static const std::regex reGP("GP([0-9]{3,4})x([0-9]{3,4})");
    if (std::regex_search(header, m, reGP)) {
        g.width = std::stoi(m[1].str());
        g.height = std::stoi(m[2].str());
        return g.width > 0 && g.height > 0;
    }

    return false;
}

static bool decode8(const std::vector<uint8_t> &raw, int cells, std::vector<float> &values) {
    if (static_cast<int>(raw.size()) < cells) return false;
    values.resize(static_cast<size_t>(cells));
    for (int i = 0; i < cells; ++i) {
        const uint8_t v = raw[static_cast<size_t>(i)];
        if (v >= 250) {
            values[static_cast<size_t>(i)] = std::numeric_limits<float>::quiet_NaN();
        } else {
            values[static_cast<size_t>(i)] = static_cast<float>(v);
        }
    }
    return true;
}

static bool decode16(const std::vector<uint8_t> &raw, int cells, std::vector<float> &values) {
    if (static_cast<int>(raw.size()) < cells * 2) return false;
    values.resize(static_cast<size_t>(cells));
    for (int i = 0; i < cells; ++i) {
        const uint16_t be = static_cast<uint16_t>((raw[static_cast<size_t>(i * 2)] << 8) | raw[static_cast<size_t>(i * 2 + 1)]);
        const bool nodata = (be & 0x2000u) != 0u;
        const uint16_t payload = static_cast<uint16_t>(be & 0x0FFFu);
        if (nodata || payload == 0) {
            values[static_cast<size_t>(i)] = std::numeric_limits<float>::quiet_NaN();
        } else {
            values[static_cast<size_t>(i)] = static_cast<float>(payload);
        }
    }
    return true;
}

static bool normalize(std::vector<float> &values) {
    std::vector<float> finite;
    finite.reserve(values.size());
    for (float v : values) {
        if (std::isfinite(v)) finite.push_back(v);
    }
    if (finite.empty()) return false;

    std::sort(finite.begin(), finite.end());
    const auto pct = [&](double p) {
        const size_t idx = static_cast<size_t>(p * static_cast<double>(finite.size() - 1));
        return finite[idx];
    };

    float lo = pct(0.05);
    float hi = pct(0.95);
    if (!(hi > lo)) {
        lo = finite.front();
        hi = finite.back();
        if (!(hi > lo)) hi = lo + 1.0f;
    }

    for (float &v : values) {
        if (!std::isfinite(v)) {
            v = 0.0f;
            continue;
        }
        v = (v - lo) / (hi - lo);
        if (v < 0.0f) v = 0.0f;
        if (v > 1.0f) v = 1.0f;
    }
    return true;
}

static void colorize(const std::vector<float> &norm, std::vector<uint8_t> &rgb) {
    struct Stop { float t; uint8_t r, g, b; };
    static const Stop stops[] = {
        {0.0f, 13, 31, 76},
        {0.25f, 37, 164, 210},
        {0.5f, 71, 176, 74},
        {0.75f, 250, 212, 70},
        {1.0f, 214, 53, 55},
    };

    rgb.resize(norm.size() * 3);
    for (size_t i = 0; i < norm.size(); ++i) {
        const float x = norm[i];
        size_t j = 0;
        while (j + 1 < std::size(stops) && x > stops[j + 1].t) {
            ++j;
        }
        const auto &a = stops[j];
        const auto &b = stops[std::min(j + 1, std::size(stops) - 1)];
        const float span = std::max(1e-6f, b.t - a.t);
        const float k = std::clamp((x - a.t) / span, 0.0f, 1.0f);

        rgb[i * 3 + 0] = static_cast<uint8_t>(a.r + (b.r - a.r) * k);
        rgb[i * 3 + 1] = static_cast<uint8_t>(a.g + (b.g - a.g) * k);
        rgb[i * 3 + 2] = static_cast<uint8_t>(a.b + (b.b - a.b) * k);
    }
}

static bool writePPM(const fs::path &dst, int w, int h, const std::vector<uint8_t> &rgb) {
    std::ofstream f(dst, std::ios::binary);
    if (!f) return false;
    f << "P6\n" << w << ' ' << h << "\n255\n";
    f.write(reinterpret_cast<const char *>(rgb.data()), static_cast<std::streamsize>(rgb.size()));
    return f.good();
}

static bool decodeOne(const fs::path &src, const fs::path &dst) {
    std::vector<uint8_t> buf;
    if (!readFile(src, buf)) return false;
    if (buf.size() < 64) return false;

    const auto etx = std::find(buf.begin(), buf.end(), static_cast<uint8_t>(0x03));
    if (etx == buf.end()) return false;

    const size_t headerLen = static_cast<size_t>(std::distance(buf.begin(), etx));
    if (headerLen < 16 || headerLen > 4096) return false;

    const std::string header(reinterpret_cast<const char *>(buf.data()), headerLen);
    Grid g;
    if (!parseGrid(header, g)) return false;

    const int cells = g.width * g.height;
    if (cells <= 0) return false;

    const size_t dataOff = headerLen + 1;
    if (dataOff >= buf.size()) return false;

    std::vector<uint8_t> raw(buf.begin() + static_cast<std::ptrdiff_t>(dataOff), buf.end());
    std::vector<float> values;

    // Only decode uncompressed grids here. Compressed variants (e.g. run-length)
    // would otherwise produce striped garbage when interpreted as raw raster.
    const size_t cells8 = static_cast<size_t>(cells);
    const size_t cells16 = static_cast<size_t>(cells) * 2;
    const size_t tol = std::max<size_t>(64, static_cast<size_t>(cells / 20));
    const bool plausible8 = raw.size() >= cells8 && raw.size() <= (cells8 + tol);
    const bool plausible16 = raw.size() >= cells16 && raw.size() <= (cells16 + tol);
    if (!plausible8 && !plausible16) {
        return false;
    }

    bool ok = false;
    if (plausible16) {
        ok = decode16(raw, cells, values);
    }
    if (!ok && plausible8) {
        ok = decode8(raw, cells, values);
    }
    if (!ok) return false;
    if (!normalize(values)) return false;

    std::vector<uint8_t> rgb;
    colorize(values, rgb);
    return writePPM(dst, g.width, g.height, rgb);
}

int main(int argc, char **argv) {
    std::string inputDir;
    std::string outputDir;
    int maxFiles = 12;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--input-dir" && i + 1 < argc) {
            inputDir = argv[++i];
        } else if (a == "--output-dir" && i + 1 < argc) {
            outputDir = argv[++i];
        } else if (a == "--max-files" && i + 1 < argc) {
            maxFiles = std::max(1, std::stoi(argv[++i]));
        } else {
            std::cerr << "unknown arg: " << a << "\n";
            return 1;
        }
    }

    if (inputDir.empty() || outputDir.empty()) {
        std::cerr << "usage: decode_radolan --input-dir DIR --output-dir DIR [--max-files N]\n";
        return 1;
    }

    std::error_code ec;
    fs::create_directories(outputDir, ec);

    std::vector<fs::path> candidates;
    for (auto it = fs::recursive_directory_iterator(inputDir, ec); it != fs::recursive_directory_iterator(); it.increment(ec)) {
        if (ec) break;
        if (!it->is_regular_file()) continue;
        const fs::path p = it->path();
        const std::string name = p.filename().string();
        std::string lower = name;
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

        if (lower.ends_with(".png") || lower.ends_with(".jpg") || lower.ends_with(".jpeg") || lower.ends_with(".gif") ||
            lower.ends_with(".webp") || lower.ends_with(".ppm") || lower.ends_with(".json") || lower.ends_with(".txt") ||
            lower.ends_with(".xml") || lower.ends_with(".html")) {
            continue;
        }

        if (fs::file_size(p, ec) < 256) continue;
        candidates.push_back(p);
    }

    std::sort(candidates.begin(), candidates.end());

    int decoded = 0;
    for (const auto &src : candidates) {
        if (decoded >= maxFiles) break;
        const std::string name = std::string("decoded_") + (decoded < 10 ? "0" : "") + std::to_string(decoded) + ".ppm";
        const fs::path dst = fs::path(outputDir) / name;
        if (decodeOne(src, dst)) {
            ++decoded;
        }
    }

    if (decoded == 0) {
        std::cerr << "no radolan files decoded\n";
        return 2;
    }

    std::cout << "decoded=" << decoded << "\n";
    return 0;
}

"""In-memory mobile port of Pipeline_DetectorCupom/pipeline.sh.

The public entry points deliberately return JSON so the Java/Python boundary is
small and deterministic. Camera frames arrive as a compact NV21 byte array;
still images are decoded from their path. No intermediate JSON or image files
are created while preview is running.
"""

import json
import cv2
import numpy as np


RDP_EARLY_EXIT = 0.30
HOUGH_EARLY_EXIT = 0.28
FALLBACK_LOCK = 0.22
CONSENSUS_IOU = 0.80
FFT_CUTOFF = 0.222
WATERSHED_MAX_AREA = 0.90
PREVIEW_DARK_P95 = 45
PREVIEW_DARK_MEAN = 30
PREVIEW_LOW_CONTRAST = 25


def _rejected(engine="none", **extra):
    result = {
        "valid": False,
        "found": False,
        "score": 0.0,
        "points": [],
        "engine": engine,
        "fftScore": None,
    }
    result.update(extra)
    return result


def _candidate(found=False, score=0.0, points=None, engine="none"):
    return {
        "found": bool(found),
        "score": float(score),
        "points": points if found and points is not None else [],
        "engine": engine,
    }


def _order_points(points):
    """Return TL, TR, BR, BL with a frame-stable corner identity.

    ``boxPoints`` and contour/RDP traversal don't guarantee their first point
    across frames. The live overlay interpolates point *indices*, therefore a
    changing traversal order makes an otherwise stationary quadrilateral look
    as if it rotates around itself. Ordering by angle around the centroid and
    then rotating to top-left gives every engine the same contract.
    """
    pts = np.asarray(points, dtype=np.float32).reshape(4, 2)
    center = np.mean(pts, axis=0)
    angles = np.arctan2(pts[:, 1] - center[1], pts[:, 0] - center[0])
    ordered = pts[np.argsort(angles)]
    top_left = int(np.argmin(np.sum(ordered, axis=1)))
    return np.roll(ordered, -top_left, axis=0)


def _geometry_score(points, shape):
    height, width = shape[:2]
    image_area = float(width * height)
    pts = np.asarray(points, dtype=np.float32).reshape(4, 2)
    relative_area = abs(float(cv2.contourArea(pts))) / image_area if image_area else 0.0
    max_cosine = 0.0
    for index in range(4):
        first = pts[(index + 3) % 4] - pts[index]
        second = pts[(index + 1) % 4] - pts[index]
        norm_product = np.linalg.norm(first) * np.linalg.norm(second)
        if norm_product > 1e-5:
            max_cosine = max(max_cosine, abs(float(np.dot(first, second) / norm_product)))
    return relative_area * (1.0 - max_cosine)


def _line_points(line):
    rho, theta = line[0]
    cosine, sine = np.cos(theta), np.sin(theta)
    x0, y0 = cosine * rho, sine * rho
    return (
        int(x0 + 1000 * -sine),
        int(y0 + 1000 * cosine),
        int(x0 - 1000 * -sine),
        int(y0 - 1000 * cosine),
    )


def _is_perpendicular(first, second, threshold=0.3):
    vector1 = np.array([first[0] - first[2], first[1] - first[3]], dtype=np.float64)
    vector2 = np.array([second[0] - second[2], second[1] - second[3]], dtype=np.float64)
    divisor = np.linalg.norm(vector1) * np.linalg.norm(vector2)
    return divisor > 1e-9 and abs(float(np.dot(vector1, vector2) / divisor)) <= threshold


def _intersection(first, second):
    denominator1 = first[0] - first[2] or 0.0001
    denominator2 = second[0] - second[2] or 0.0001
    slope1 = (first[1] - first[3]) / denominator1
    slope2 = (second[1] - second[3]) / denominator2
    if abs(slope1 - slope2) < 1e-9:
        return None
    intercept1 = slope1 * -first[0] + first[1]
    intercept2 = slope2 * -second[0] + second[1]
    x_value = (intercept2 - intercept1) / (slope1 - slope2)
    return int(x_value), int(x_value * slope1 + intercept1)


def _quadrant_points(intersections, height, width):
    buckets = [[], [], [], []]
    middle_y, middle_x = height // 2, width // 2
    for point in intersections:
        if point[0] < middle_x and point[1] < middle_y:
            buckets[0].append(point)
        elif point[0] > middle_x and point[1] < middle_y:
            buckets[1].append(point)
        elif point[0] > middle_x and point[1] > middle_y:
            buckets[2].append(point)
        else:
            buckets[3].append(point)
    if any(not bucket for bucket in buckets):
        return None
    return [[sum(p[0] for p in bucket) / len(bucket), sum(p[1] for p in bucket) / len(bucket)] for bucket in buckets]


def _run_hough(image):
    """Motor 2: semantic port of run_hough.py and filter_has_document."""
    gray = image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    kernel = np.ones((8, 8), np.uint8)
    morph = cv2.dilate(gray, kernel, iterations=11)
    morph = cv2.erode(morph, kernel, iterations=11)

    for attempt in range(3):
        canny = cv2.Canny(morph, 60 - attempt * 20, 130 - attempt * 20, apertureSize=3)
        horizontal = cv2.HoughLines(
            canny, 1, np.pi / 180, 25, srn=3, stn=0,
            min_theta=np.radians(90 - attempt * 6),
            max_theta=np.radians(100 + attempt * 6),
        )
        vertical = cv2.HoughLines(
            canny, 1, np.pi / 180, 25, srn=3, stn=0,
            min_theta=np.radians(-10 - attempt * 6),
            max_theta=np.radians(5 + attempt * 6),
        )
        horizontal_points = [] if horizontal is None else [_line_points(item) for item in horizontal[:4]]
        vertical_points = [] if vertical is None else [_line_points(item) for item in vertical[:4]]
        intersections = []
        for horizontal_line in horizontal_points:
            for vertical_line in vertical_points:
                if _is_perpendicular(horizontal_line, vertical_line):
                    point = _intersection(horizontal_line, vertical_line)
                    if point is not None:
                        intersections.append(point)
        points = _quadrant_points(intersections, image.shape[0], image.shape[1])
        if points is not None:
            score = _geometry_score(points, image.shape)
            return _candidate(True, score, np.int32(points).tolist(), "python_hough")
    return _candidate(engine="python_hough")


def _run_watershed(image):
    """Motor 3: in-memory port with the mandatory <90% area guard."""
    bgr = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR) if image.ndim == 2 else image
    resized = cv2.resize(bgr, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
    blurred = cv2.medianBlur(gray, 7)
    binary = cv2.adaptiveThreshold(
        blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 45, 2
    )
    kernel = np.ones((3, 3), np.uint8)
    closed = cv2.morphologyEx(binary, cv2.MORPH_ERODE, kernel, iterations=2)
    closed = cv2.morphologyEx(closed, cv2.MORPH_CLOSE, kernel, iterations=2)

    count, components = cv2.connectedComponents(closed)
    if count <= 1:
        foreground = np.zeros_like(closed, dtype=np.uint8)
    else:
        sizes = np.bincount(components.ravel())
        foreground = (components == np.argmax(sizes[1:]) + 1).astype(np.uint8) * 255
    foreground = cv2.morphologyEx(foreground, cv2.MORPH_CLOSE, kernel, iterations=8)

    unknown_seed = (foreground == 0).astype(np.uint8)
    count, components = cv2.connectedComponents(unknown_seed)
    if count <= 1:
        background = np.zeros_like(foreground, dtype=np.uint8)
    else:
        sizes = np.bincount(components.ravel())
        background = (components == np.argmax(sizes[1:]) + 1).astype(np.uint8) * 255
    background = cv2.erode(background, kernel, iterations=20)
    unknown = cv2.bitwise_not(cv2.bitwise_or(foreground, background))

    markers = cv2.connectedComponents(foreground)[1].astype(np.int32)
    markers[unknown == 255] = 0
    markers[markers > 0] += 1
    markers[background == 255] = 1
    flooded = cv2.watershed(resized, markers.copy())

    labels, counts = np.unique(flooded, return_counts=True)
    valid_mask = (labels > 1) & (labels != -1)
    valid_labels = labels[valid_mask]
    if len(valid_labels) == 0:
        return _candidate(engine="python_watershed")
    label = valid_labels[np.argmax(counts[valid_mask])]
    if counts[labels == label][0] <= 0.25 * flooded.size:
        return _candidate(engine="python_watershed")
    mask = (flooded == label).astype(np.uint8) * 255
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return _candidate(engine="python_watershed")
    hull = cv2.convexHull(max(contours, key=cv2.contourArea))
    perimeter = cv2.arcLength(hull, True)
    epsilon = 0.02
    polygon = cv2.approxPolyDP(hull, epsilon * perimeter, True)
    while len(polygon) > 6 and epsilon < 1.0:
        epsilon += 0.02
        polygon = cv2.approxPolyDP(hull, epsilon * perimeter, True)
    if not 3 <= len(polygon) <= 6:
        return _candidate(engine="python_watershed")
    rect_width, rect_height = cv2.minAreaRect(polygon)[1]
    rect_area = rect_width * rect_height
    if rect_area <= 0 or cv2.contourArea(polygon) / rect_area < 0.7:
        return _candidate(engine="python_watershed")

    points = np.int32(cv2.boxPoints(cv2.minAreaRect(polygon)) * 2.0)
    relative_area = abs(float(cv2.contourArea(points))) / float(image.shape[0] * image.shape[1])
    if relative_area >= WATERSHED_MAX_AREA:
        return _candidate(engine="python_watershed_area_guard")
    return _candidate(True, _geometry_score(points, image.shape), points.tolist(), "python_watershed")


def _iou(first, second):
    first = _order_points(first)
    second = _order_points(second)
    area_first = abs(float(cv2.contourArea(first)))
    area_second = abs(float(cv2.contourArea(second)))
    if area_first == 0 or area_second == 0:
        return 0.0
    intersection_area, _ = cv2.intersectConvexConvex(first, second)
    union = area_first + area_second - intersection_area
    return float(intersection_area / union) if union > 0 else 0.0


def _arbitrate(candidates):
    valid = [item for item in candidates if item["found"]]
    for first_index, first in enumerate(valid):
        for second in valid[first_index + 1:]:
            if _iou(first["points"], second["points"]) >= CONSENSUS_IOU:
                blended = np.int32((_order_points(first["points"]) + _order_points(second["points"])) / 2.0)
                return _candidate(
                    True,
                    max(first["score"], second["score"]),
                    blended.tolist(),
                    "consensus_%s_%s" % (first["engine"], second["engine"]),
                )
    if not valid:
        return _candidate(engine="arbiter")
    best = max(valid, key=lambda item: item["score"])
    return best if best["score"] >= FALLBACK_LOCK else _candidate(engine="arbiter_fallback_lock")


def _warp(image, points):
    top_left, top_right, bottom_right, bottom_left = _order_points(points)
    width = max(np.linalg.norm(bottom_right - bottom_left), np.linalg.norm(top_right - top_left))
    height = max(np.linalg.norm(top_right - bottom_right), np.linalg.norm(top_left - bottom_left))
    width, height = max(int(width), 1), max(int(height), 1)
    destination = np.array(
        [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
        dtype=np.float32,
    )
    transform = cv2.getPerspectiveTransform(_order_points(points), destination)
    return cv2.warpPerspective(image, transform, (width, height))


def _fft_score(warped, mask_percentage=0.6):
    gray = warped if warped.ndim == 2 else cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY)
    spectrum = np.fft.fftshift(np.fft.fft2(gray.astype(np.float32) / 255.0))
    height, width = spectrum.shape
    center_x, center_y = width // 2, height // 2
    center_height, center_width = int(height * mask_percentage), int(width * mask_percentage)
    cropped = spectrum[
        center_y - center_height // 2:center_y + center_height // 2,
        center_x - center_width // 2:center_x + center_width // 2,
    ]
    magnitude = np.log1p(np.abs(cropped)) * 255
    minimum, maximum = float(np.min(magnitude)), float(np.max(magnitude))
    if maximum == minimum:
        return 0.0
    return float(np.mean((magnitude - minimum) / (maximum - minimum)))


def _preview_is_too_dark(image):
    """Reject a covered/underexposed camera before line detectors see noise."""
    gray = image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    mean = float(np.mean(gray))
    p05, p95 = np.percentile(gray, (5, 95))
    contrast = float(p95 - p05)
    return p95 < PREVIEW_DARK_P95 or (
        mean < PREVIEW_DARK_MEAN and contrast < PREVIEW_LOW_CONTRAST
    )


def _run(image, rdp_points, rdp_score):
    rdp = _candidate(bool(rdp_points), rdp_score, rdp_points, "cpp_rdp_hough")
    if rdp["found"] and rdp["score"] >= RDP_EARLY_EXIT:
        selected = rdp
    else:
        hough = _run_hough(image)
        if hough["found"] and hough["score"] >= HOUGH_EARLY_EXIT:
            selected = hough
        else:
            watershed = _run_watershed(image)
            selected = _arbitrate([rdp, hough, watershed])

    if not selected["found"]:
        return _rejected(selected["engine"])
    # This is also the order emitted to Kotlin/Flutter. Do it before both the
    # warp and the return path so RDP early-exit, Hough and Watershed never
    # assign a different semantic corner to the same list index.
    selected["points"] = np.int32(_order_points(selected["points"])).tolist()
    warped = _warp(image, selected["points"])
    fft_score = _fft_score(warped)
    if fft_score <= FFT_CUTOFF:
        return _rejected("fft_rejected", fftScore=fft_score)
    selected.update({"valid": True, "fftScore": fft_score})
    return selected


def process_frame(nv21, width, height, rotation_degrees, rdp_points, rdp_score):
    try:
        width, height = int(width), int(height)
        yuv = np.frombuffer(nv21, dtype=np.uint8).reshape(height + height // 2, width)
        image = cv2.cvtColor(yuv, cv2.COLOR_YUV2BGR_NV21)
        rotation = int(rotation_degrees)
        if rotation == 90:
            image = cv2.rotate(image, cv2.ROTATE_90_CLOCKWISE)
        elif rotation == 180:
            image = cv2.rotate(image, cv2.ROTATE_180)
        elif rotation == 270:
            image = cv2.rotate(image, cv2.ROTATE_90_COUNTERCLOCKWISE)
        if _preview_is_too_dark(image):
            return json.dumps(_rejected("underexposed_preview"), separators=(",", ":"))
        points = [] if rdp_points is None else np.asarray(rdp_points, dtype=np.float64).reshape(-1, 2).tolist()
        return json.dumps(_run(image, points, float(rdp_score)), separators=(",", ":"))
    except Exception as error:
        return json.dumps(_rejected("pipeline_error", error=str(error)), separators=(",", ":"))


def process_encoded_image(encoded_image, rdp_points, rdp_score):
    try:
        image = cv2.imdecode(
            np.frombuffer(encoded_image, dtype=np.uint8),
            cv2.IMREAD_COLOR,
        )
        if image is None:
            raise ValueError("encoded image could not be decoded")
        points = [] if rdp_points is None else np.asarray(rdp_points, dtype=np.float64).reshape(-1, 2).tolist()
        return json.dumps(_run(image, points, float(rdp_score)), separators=(",", ":"))
    except Exception as error:
        return json.dumps(_rejected("pipeline_error", error=str(error)), separators=(",", ":"))


def evaluate_encoded_crop(encoded_crop):
    """FFT-only endpoint for the preview-scaled capture path."""
    try:
        crop = cv2.imdecode(
            np.frombuffer(encoded_crop, dtype=np.uint8),
            cv2.IMREAD_COLOR,
        )
        if crop is None:
            raise ValueError("encoded crop could not be decoded")
        score = _fft_score(crop)
        return json.dumps(
            {"valid": score > FFT_CUTOFF, "fftScore": score},
            separators=(",", ":"),
        )
    except Exception as error:
        return json.dumps(
            {"valid": False, "fftScore": 0.0, "error": str(error)},
            separators=(",", ":"),
        )

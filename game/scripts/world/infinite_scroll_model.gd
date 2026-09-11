class_name InfiniteScrollModel
extends RefCounted
## SCROLL / RECYCLING logic for the vertical level map, kept as pure math with
## NO scene-tree dependency so it is fully unit-testable and can't drift from
## the visual layer.
##
## The map is virtualized: a bounded pool of visual nodes is mapped onto a run
## of logical level indices `min_index .. max_index`. Scrolling only changes
## `scroll_offset` (content-space pixels, 0 == level `min_index` at the
## anchor); `layout()` then reports which logical indices should be on screen
## and where, never more than `pool_size` of them and never past `max_index`.
## Nothing is instantiated or freed here — the owner reuses the same nodes and
## just re-assigns their data. `max_index` (100 by default) is the only limit
## and is trivially raised.

## Vertical distance between consecutive level anchors, in content pixels.
var row_spacing: float = 360.0
## Hard cap on live visual nodes. `layout()` never returns more than this.
var pool_size: int = 9
## Extra rows kept populated just outside the viewport, each side, so a fast
## fling never reveals an empty gap before recycling catches up.
var buffer_rows: int = 2
## Lowest logical level index (the map never scrolls above it).
var min_index: int = 1
## Highest logical level index this island exposes (extensible).
var max_index: int = 100
## Y (content space) of level `min_index`'s anchor — a top margin so the first
## island isn't jammed against the header.
var top_margin: float = 220.0
## Extra space kept below the last level so it isn't jammed against the edge.
var bottom_margin: float = 260.0

func _init(p_row_spacing: float = 360.0, p_pool_size: int = 9, p_buffer_rows: int = 2) -> void:
	row_spacing = p_row_spacing
	pool_size = maxi(p_pool_size, 1)
	buffer_rows = maxi(p_buffer_rows, 0)

## Content-space Y of a logical level's anchor point.
func content_y_for(index: int) -> float:
	return top_margin + float(index - min_index) * row_spacing

## Total scrollable content height for the current index range.
func content_height() -> float:
	return content_y_for(max_index) + bottom_margin

## Largest valid scroll offset for a viewport — keeps `max_index` reachable
## without scrolling into empty space past the end.
func max_scroll(viewport_h: float) -> float:
	return maxf(content_height() - viewport_h, 0.0)

## Clamp a desired scroll offset to [0, max_scroll]. Needs the viewport height
## for the upper bound.
func clamp_offset(offset: float, viewport_h: float) -> float:
	return clampf(offset, 0.0, max_scroll(viewport_h))

## Scroll offset that places `index` at `frac` down the viewport
## (frac 0 == top, 0.5 == centre). Used to jump to the player's current level.
func offset_to_focus(index: int, viewport_h: float, frac: float = 0.4) -> float:
	return clamp_offset(content_y_for(index) - viewport_h * frac, viewport_h)

## First logical index whose anchor is at/below the top buffer edge.
func first_index(scroll_offset: float, _viewport_h: float) -> int:
	var raw := int(floor((scroll_offset - top_margin) / row_spacing)) + min_index
	return clampi(raw - buffer_rows, min_index, max_index)

## How many rows fit in the viewport plus both buffers (uncapped by pool).
func window_rows(viewport_h: float) -> int:
	return int(ceil(viewport_h / row_spacing)) + 1 + buffer_rows * 2

## The virtualization plan for the current scroll position: an ordered array
## of { "index": int, "y": float } where `y` is the on-screen anchor Y
## (content_y - scroll_offset). Length is ALWAYS <= pool_size and never
## includes an index past `max_index`, so the owner maps entry i onto pooled
## node i and hides any leftover node.
func layout(scroll_offset: float, viewport_h: float) -> Array:
	var offset := clamp_offset(scroll_offset, viewport_h)
	var start := first_index(offset, viewport_h)
	var want := mini(window_rows(viewport_h), pool_size)
	var out: Array = []
	for i in want:
		var idx := start + i
		if idx > max_index:
			break
		out.append({"index": idx, "y": content_y_for(idx) - offset})
	return out

## True when a given logical index is currently within the populated window
## (viewport + buffers) for this scroll offset.
func is_index_live(index: int, scroll_offset: float, viewport_h: float) -> bool:
	for entry in layout(scroll_offset, viewport_h):
		if int(entry["index"]) == index:
			return true
	return false

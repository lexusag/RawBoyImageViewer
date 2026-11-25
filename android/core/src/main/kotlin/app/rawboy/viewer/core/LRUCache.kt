package app.rawboy.viewer.core

/**
 * A thread-safe least-recently-used cache limited by the total cost of its values (bytes, for images).
 * A port of RawBoyBrowseKit's `LRUCache.swift`: keep the two in step.
 */
class LRUCache<K, V>(val budget: Int) {
    private class Entry<V>(val value: V, val cost: Int)

    private val map = LinkedHashMap<K, Entry<V>>(32, 0.75f, true)
    private var _totalCost: Int = 0

    val totalCost: Int
        @Synchronized get() = _totalCost

    val count: Int
        @Synchronized get() = map.size

    @Synchronized
    fun value(key: K): V? = map[key]?.value

    @Synchronized
    fun peek(key: K): V? {
        for ((k, v) in map) if (k == key) return v.value
        return null
    }

    @Synchronized
    fun contains(key: K): Boolean = map.containsKey(key)

    @Synchronized
    fun insert(value: V, key: K, cost: Int) {
        map.remove(key)?.let { _totalCost -= it.cost }
        map[key] = Entry(value, cost)
        _totalCost += cost
        val it = map.entries.iterator()
        while (_totalCost > budget && map.size > 1 && it.hasNext()) {
            val oldest = it.next()
            _totalCost -= oldest.value.cost
            it.remove()
        }
    }

    @Synchronized
    fun remove(key: K) {
        map.remove(key)?.let { _totalCost -= it.cost }
    }

    @Synchronized
    fun removeAll() {
        map.clear()
        _totalCost = 0
    }
}

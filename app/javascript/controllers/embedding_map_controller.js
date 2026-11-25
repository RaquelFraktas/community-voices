import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

const OLDER_WEEK_OPACITY = 0.25
const BASE_RADIUS = 4

// Draws the clustering's 2D points: colored by cluster, sized by how often each chunk was retrieved,
// with the report week's points fully opaque and older weeks faded. Clicking a point opens its post.
export default class extends Controller {
  static values = { url: String }
  static targets = ["canvas", "status"]

  async connect() {
    const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
    if (!response.ok) {
      this.statusTarget.textContent = "Could not load the embedding map."
      return
    }

    const map = await response.json()
    this.statusTarget.textContent = `${map.points.length} chunks in ${map.clusters.length} themes`
    this.chart = new Chart(this.canvasTarget, this.chartConfig(map))
  }

  disconnect() {
    this.chart?.destroy()
  }

  chartConfig(map) {
    return {
      type: "scatter",
      data: { datasets: map.clusters.map((cluster) => this.dataset(cluster, map.points)) },
      options: {
        animation: false,
        maintainAspectRatio: false,
        scales: { x: { display: false }, y: { display: false } },
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: (context) => [context.raw.title, context.raw.clusterLabel] } }
        },
        onClick: (_event, elements) => this.openPost(elements),
        onHover: (event, elements) => { event.native.target.style.cursor = elements.length ? "pointer" : "default" }
      }
    }
  }

  dataset(cluster, points) {
    const members = points.filter((point) => point.cluster_id === cluster.id)
    return {
      label: cluster.label,
      data: members.map((point) => ({
        x: point.x, y: point.y, title: point.title, url: point.url, clusterLabel: point.cluster_label
      })),
      pointRadius: members.map((point) => BASE_RADIUS + 2 * Math.sqrt(point.retrievals_count)),
      pointHoverRadius: members.map((point) => BASE_RADIUS + 2 + 2 * Math.sqrt(point.retrievals_count)),
      backgroundColor: members.map((point) => withOpacity(cluster.color, point.in_report_week ? 1 : OLDER_WEEK_OPACITY)),
      borderColor: members.map((point) => withOpacity(cluster.color, point.in_report_week ? 1 : OLDER_WEEK_OPACITY))
    }
  }

  openPost(elements) {
    if (!elements.length) return

    const { datasetIndex, index } = elements[0]
    const point = this.chart.data.datasets[datasetIndex].data[index]
    window.open(point.url, "_blank", "noopener")
  }
}

function withOpacity(hexColor, opacity) {
  const [r, g, b] = [1, 3, 5].map((start) => parseInt(hexColor.slice(start, start + 2), 16))
  return `rgba(${r}, ${g}, ${b}, ${opacity})`
}

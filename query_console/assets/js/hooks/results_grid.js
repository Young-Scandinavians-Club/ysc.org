import {TabulatorFull as Tabulator} from "tabulator-tables"

const ResultsGrid = {
  mounted() {
    this.table = new Tabulator(this.el, {
      data: [],
      columns: [],
      layout: "fitDataStretch",
      height: "100%",
      placeholder: "No results",
      movableColumns: true,
      resizableColumns: true
    })

    this.handleEvent("results", ({columns, rows, truncated}) => {
      const cols = (columns || []).map((name) => ({
        title: name,
        field: name,
        headerSort: true,
        sorter: "string"
      }))

      const data = (rows || []).map((row) => {
        const obj = {}
        ;(columns || []).forEach((name, i) => {
          obj[name] = row[i]
        })
        return obj
      })

      this.table.setColumns(cols)
      this.table.replaceData(data)

      if (truncated) {
        this.el.dataset.truncated = "true"
      } else {
        delete this.el.dataset.truncated
      }
    })
  },

  destroyed() {
    if (this.table) this.table.destroy()
  }
}

export default ResultsGrid

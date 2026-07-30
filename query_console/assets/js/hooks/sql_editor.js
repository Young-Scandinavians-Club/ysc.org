import {EditorState, Compartment} from "@codemirror/state"
import {EditorView, keymap, lineNumbers, highlightActiveLine, drawSelection} from "@codemirror/view"
import {defaultKeymap, history, historyKeymap} from "@codemirror/commands"
import {sql, PostgreSQL} from "@codemirror/lang-sql"
import {autocompletion} from "@codemirror/autocomplete"

const SqlEditor = {
  mounted() {
    this.schemaCompartment = new Compartment()
    this.debounceTimer = null
    const initialSql = this.el.dataset.sql || ""

    const extensions = [
      lineNumbers(),
      highlightActiveLine(),
      drawSelection(),
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      this.schemaCompartment.of(sql({dialect: PostgreSQL, schema: {}})),
      autocompletion(),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          clearTimeout(this.debounceTimer)
          this.debounceTimer = setTimeout(() => {
            this.pushEvent("sql_changed", {sql: update.state.doc.toString()})
          }, 400)
        }
      }),
      EditorView.theme({
        "&": {height: "100%", fontSize: "13px"},
        ".cm-scroller": {overflow: "auto", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"},
        ".cm-content": {padding: "12px 0"}
      })
    ]

    this.view = new EditorView({
      state: EditorState.create({doc: initialSql, extensions}),
      parent: this.el
    })

    this.handleEvent("schema", ({schema}) => {
      this.view.dispatch({
        effects: this.schemaCompartment.reconfigure(
          sql({dialect: PostgreSQL, schema: schema || {}})
        )
      })
    })

    // Intercept run buttons to include current SQL / selection / statement index
    this._onRunClick = (e) => {
      const btn = e.target.closest("#run-all, #run-current, #run-selection")
      if (!btn) return
      e.preventDefault()
      e.stopPropagation()

      const sqlText = this.view.state.doc.toString()
      const sel = this.view.state.selection.main
      const selection = sel.empty ? "" : this.view.state.sliceDoc(sel.from, sel.to)
      const statementIndex = this.currentStatementIndex(sqlText, sel.head)

      const event =
        btn.id === "run-all" ? "run_all" :
        btn.id === "run-current" ? "run_current" : "run_selection"

      this.pushEvent(event, {
        sql: sqlText,
        selection,
        statement_index: statementIndex
      })
    }

    document.addEventListener("click", this._onRunClick, true)
  },

  currentStatementIndex(sqlText, pos) {
    // Approximate: count semicolons before caret among non-empty segments
    const before = sqlText.slice(0, pos)
    const parts = before.split(";")
    let idx = Math.max(0, parts.length - 1)
    // If caret is right after a semicolon on empty trailing segment, stay on previous
    if (parts[parts.length - 1].trim() === "" && idx > 0) idx -= 1
    return idx
  },

  destroyed() {
    clearTimeout(this.debounceTimer)
    if (this._onRunClick) document.removeEventListener("click", this._onRunClick, true)
    if (this.view) this.view.destroy()
  }
}

export default SqlEditor

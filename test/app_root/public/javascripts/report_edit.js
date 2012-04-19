// TODO: This whole file is ugly, there must be a trillion
// better ways to do this with widget toolkits.

var report_settings_possible_layers = [];
function add_possible_layer(label, clsname) {
  report_settings_possible_layers.push([label, clsname]);
}

var report_settings_possible_aggregate_sources = [];
function add_possible_aggregate_source(label, name) {
  report_settings_possible_aggregate_sources.push([label, name]);
}

var ReportSettingList = function(ul, name, choice_f, options, prev) {
  this.ul = $(ul);
  this.li = null;
  this.sel_elem = null;
  this.name = name;
  this.choice_f = choice_f;
  this.next = null;
  this.prev = prev || null;
  this.initialized = false;
  this.values_to_preload = [];
  this.options = {
    "label_f": null,
    "limit": null
  }
  if (options) { Object.extend(this.options, options); }

  if (document.loaded) {
    this.initialize();
  } else {
    Event.observe(document, 'dom:loaded', this.initialize.bind(this), false);
  }
}

ReportSettingList.prototype = {
  initialize: function() {
    this.li = new Element('li');
    if (this.options["label_f"]) {
      this.li.insert(this.options["label_f"](this) + ": ");
    }

    var select = new Element('select', {'name': this.name + "[]"});
    this.sel_elem = select;
    var empty_option = new Element('option', {'value': ''});
    select.insert(empty_option);
    this.choice_f(this).each(function(c) {
      var option = new Element('option', {'value': c[1]});
      option.insert(c[0]);
      select.insert(option);
    })

    this.li.insert(select);
    this.ul.insert(this.li);
    this.sel_elem.observe("change", this.handle_change.bind(this));

    this.unpack_values_to_preload();
    this.initialized = true;
  },

  choices: function() {
    return this.choice_f(this);
  },

  destroy_li: function() {
    if (this.next) {
      this.next.destroy_li();
    }
    if (this.li) {
      this.li.remove();
      this.li = null;
    }
  },

  handle_change: function() {
    if (this.next) { this.next.destroy_li(); }
    if (this.selected_value()) {
      if (this.options["limit"] != null) {
        if (this.num_prev()+1 >= this.options["limit"]) {
          return
        }
      }
      var next_rsl = new ReportSettingList(
        this.ul, this.name, this.choice_f, this.options, this
      );
      if (next_rsl.choices().size() > 0) {
        this.next = next_rsl;
      } else {
        next_rsl.destroy_li();
      }
    } else {
      this.next = null;
    }
  },

  num_prev: function() {
    if (this.prev) {
      return 1 + this.prev.num_prev();
    } else {
      return 0;
    }
  },

  selected_value: function() {
    var v = this.sel_elem.options[this.sel_elem.selectedIndex].value;
    if (v == "") {
      return null;
    } else {
      return v;
    }
  },

  values_to_here: function() {
    var r = [];
    if (this.prev) {
      r = this.prev.values_to_here();
    }
    var v = this.selected_value();
    if (v) {
      r.push(v);
    }
    return r;
  },

  preload_value: function(v) {
    this.values_to_preload.push(v);
    if (this.initialized) {
      this.unpack_values_to_preload();
    }
  },

  unpack_values_to_preload: function() {
    var me = this;
    me.values_to_preload.each(function(v) {
      if (me.selected_value() == null) {
        var idx = null;
        me.choices().each(function(e, i) {
          if (e[1] == v) {
            idx = i;
            throw $break;
          }
        })
        if (idx != null) {
          me.sel_elem.selectedIndex = idx+1;
          me.handle_change();
        }
      } else if (me.next) {
        me.next.preload_value(v);
      }
    })
  }
}

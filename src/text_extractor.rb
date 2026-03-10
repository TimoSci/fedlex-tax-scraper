
# Converts fedlex HTML pages into clean Markdown, stripping navigation chrome.

module TextExtractor
  def self.from_html(html_body)
    doc = Nokogiri::HTML(html_body)

    # Remove scripts, styles, navigation, headers/footers
    %w[script style nav header footer .navbar .breadcrumb .sidebar
       .menu .print-info [role="navigation"]].each do |selector|
      doc.css(selector).remove
    end

    # Fedlex HTML uses specific article containers; try to target the law body
    body_node = doc.at_css('article, .page-content, main, #content, body')
    return '' unless body_node

    # Convert HTML to Markdown, preserving structure
    lines = []
    convert_node(body_node, lines)
    lines.join("\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def self.convert_node(node, lines, list_depth: 0)
    node.children.each do |child|
      if child.text?
        text = child.text.strip
        lines << text unless text.empty?
      elsif child.element?
        tag = child.name.downcase
        case tag
        when 'h1'
          lines << ""
          lines << "# #{child.text.strip}"
          lines << ""
        when 'h2'
          lines << ""
          lines << "## #{child.text.strip}"
          lines << ""
        when 'h3'
          lines << ""
          lines << "### #{child.text.strip}"
          lines << ""
        when 'h4'
          lines << ""
          lines << "#### #{child.text.strip}"
          lines << ""
        when 'h5', 'h6'
          lines << ""
          lines << "##### #{child.text.strip}"
          lines << ""
        when 'p'
          lines << ""
          convert_node(child, lines, list_depth: list_depth)
          lines << ""
        when 'ul', 'ol'
          lines << ""
          convert_node(child, lines, list_depth: list_depth + 1)
          lines << ""
        when 'li'
          indent = '  ' * [list_depth - 1, 0].max
          prefix = child.parent&.name&.downcase == 'ol' ? "1. " : "- "
          text = child.text.strip
          lines << "#{indent}#{prefix}#{text}" unless text.empty?
        when 'table'
          convert_table(child, lines)
        when 'br'
          lines << "  "
        when 'strong', 'b'
          lines << "**#{child.text.strip}**"
        when 'em', 'i'
          lines << "*#{child.text.strip}*"
        when 'blockquote'
          child.text.strip.split("\n").each do |line|
            lines << "> #{line.strip}"
          end
        when 'hr'
          lines << ""
          lines << "---"
          lines << ""
        else
          convert_node(child, lines, list_depth: list_depth)
        end
      end
    end
  end

  def self.convert_table(table_node, lines)
    rows = table_node.css('tr')
    return if rows.empty?

    table_data = rows.map do |row|
      row.css('th, td').map { |cell| cell.text.strip.gsub('|', '\\|') }
    end
    return if table_data.empty?

    max_cols = table_data.map(&:length).max
    table_data.each { |row| row.fill('', row.length...max_cols) }

    lines << ""
    lines << "| #{table_data.first.join(' | ')} |"
    lines << "| #{(['---'] * max_cols).join(' | ')} |"
    table_data.drop(1).each do |row|
      lines << "| #{row.join(' | ')} |"
    end
    lines << ""
  end

  private_class_method :convert_node, :convert_table
end

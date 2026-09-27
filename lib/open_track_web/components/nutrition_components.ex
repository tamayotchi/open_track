defmodule OpenTrackWeb.NutritionComponents do
  @moduledoc "Accessible charts of the signed-in user's recorded values."
  use OpenTrackWeb, :html

  alias OpenTrackWeb.NutritionChart

  attr :settings, :any, default: nil

  def targets_summary(assigns) do
    ~H"""
    <section id="targets-summary" class="targets-summary" aria-labelledby="targets-summary-title">
      <div class="section-heading">
        <h2 id="targets-summary-title">Your targets</h2>
        <.link navigate={~p"/app/account#targets"} class="text-button" id="edit-targets">
          Edit targets <.icon name="hero-pencil-square" class="size-4" />
        </.link>
      </div>
      <dl class="target-cards">
        <div>
          <dt><.icon name="hero-scale" class="size-4" /> Target weight</dt>
          <dd>
            {if @settings && @settings.target_weight_kg,
              do: @settings.target_weight_kg,
              else: "Not set"} <span>kg</span>
          </dd>
        </div>
        <div>
          <dt><.icon name="hero-chart-pie" class="size-4" /> Target body fat</dt>
          <dd>
            {if @settings && @settings.target_body_fat_percent,
              do: @settings.target_body_fat_percent,
              else: "Not set"} <span>%</span>
          </dd>
        </div>
      </dl>
      <p class="field-help mt-4">Your goals, on your terms. No automatic recommendations.</p>
    </section>
    """
  end

  attr :metric, :map, required: true
  attr :days, :integer, default: 7
  attr :expanded, :boolean, default: true
  attr :entries, :list, required: true
  attr :today, Date, required: true

  def chart(assigns) do
    assigns =
      assigns
      |> assign(
        :plot,
        NutritionChart.plot(assigns.metric, assigns.entries, assigns.days, assigns.today)
      )
      |> assign(
        :id,
        "#{assigns.metric.key}-chart"
      )

    ~H"""
    <article
      id={@id}
      class={[
        "nutrition-card",
        "nutrition-card--#{@metric.key}",
        @expanded && "nutrition-card--expanded"
      ]}
    >
      <header class="nutrition-card-heading">
        <h3>
          <span class="nutrition-icon"><.icon name={@metric.icon} class="size-4" /></span>{@metric.title}
        </h3>
        <span class="sample-week">Last {@days} days</span>
      </header>
      <p class="nutrition-average">
        <strong>{NutritionChart.format(@plot.average, @metric.precision)}</strong><span>{@metric.unit}</span>
      </p>
      <p class="nutrition-average-label">Average of recorded days · Missing days are not zero</p>
      <div
        class="chart-scroll"
        tabindex="0"
        role="region"
        aria-label={"#{@metric.title} chart, scroll for all dates"}
      >
        <svg
          viewBox={"0 0 #{@plot.width} 190"}
          class="nutrition-chart"
          style={if @expanded, do: "min-width: #{@plot.width}px"}
          role="img"
          aria-labelledby={"#{@id}-title #{@id}-description"}
        >
          <title id={"#{@id}-title"}>{@metric.title}: last {@days} days</title>
          <desc id={"#{@id}-description"}>
            Your recorded measurements. Exact values are in the table below. Unrecorded days are left blank.
          </desc>
          <g :for={tick <- @plot.ticks} class="chart-grid-line">
            <line x1="42" x2={@plot.width - 12} y1={tick.y} y2={tick.y} />
            <text x="35" y={tick.y + 3} text-anchor="end">
              {NutritionChart.format(tick.value, 0)}
            </text>
          </g>
          <g :if={@metric.kind == :line}>
            <line
              :for={[a, b] <- @plot.segments}
              x1={a.x}
              y1={a.y}
              x2={b.x}
              y2={b.y}
              class="chart-line"
            />
          </g>
          <g :for={point <- @plot.points}>
            <title>
              {Calendar.strftime(point.date, "%b %-d")}: {NutritionChart.format(
                point.value,
                @metric.precision
              )} {@metric.unit}
            </title>
            <rect
              :if={@metric.kind == :bar}
              x={point.x - point.width / 2}
              y={point.y}
              width={point.width}
              height={156 - point.y}
              rx="2"
              class="chart-bar"
            />
            <circle :if={@metric.kind == :line} cx={point.x} cy={point.y} r="4" class="chart-point" />
            <text x={point.x} y="180" text-anchor="middle" class="chart-day">
              {Calendar.strftime(point.date, if(@days == 7, do: "%a", else: "%d"))}
            </text>
          </g>
        </svg>
      </div>
      <p :if={@expanded} class="chart-date-range">
        {Calendar.strftime(@plot.first_date, "%b %-d, %Y")} – {Calendar.strftime(
          @plot.last_date,
          "%b %-d, %Y"
        )} · Your history
      </p>
      <p :if={@expanded && @days > 7} class="field-help mb-4">
        Scroll the chart to see every day, or open the values below.
      </p>
      <details class="chart-values" id={"#{@id}-values"}>
        <summary>View recorded values <.icon name="hero-chevron-down" class="size-4" /></summary>
        <div
          class="chart-table-scroll"
          tabindex="0"
          role="region"
          aria-label={"#{@metric.title} recorded values"}
        >
          <table>
            <caption class="sr-only">Your recorded {@metric.title} values</caption>
            <thead>
              <tr>
                <th scope="col">Date</th>
                <th scope="col">{@metric.unit}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={point <- @plot.points}>
                <th scope="row">{Calendar.strftime(point.date, "%b %-d, %Y")}</th>
                <td>{NutritionChart.format(point.value, @metric.precision)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </article>
    """
  end
end

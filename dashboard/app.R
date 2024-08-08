library(shiny)
library(ggplot2)
library(dplyr)
library(lubridate)
library(DALEXtra)
library(forcats)
library(mgcViz)

# Tải mô hình và dữ liệu đã lưu
gam.model <- readRDS("gam_model.rds")
cleaned_data <- readRDS("cleaned_data.rds")
explainer_gam <- readRDS("explainer_gam.rds")
reg_data <- cleaned_data[,-c(1,2,3,7,11,12,13,14,15,16,17)]
# Định nghĩa giao diện người dùng
ui <- fluidPage(
  titlePanel("Dự đoán và phân tích số lượng xe thuê"),
  sidebarLayout(
    sidebarPanel(
      dateInput("date", "Chọn ngày:",
                min = as.Date("2017-12-01"), max = as.Date("2018-11-30"), value = as.Date("2018-10-31")),
      sliderInput("hour", "Chọn giờ:",
                  min = 0, max = 23, value = 16),
      selectInput("variable", "Chọn biến để phân tích theo mùa:",
                  choices = colnames(reg_data),
                  selected = "rainfall_mm")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Dự đoán cả ngày",
                 verbatimTextOutput("daily_summary"),
                 plotOutput("daily_plot")),
        tabPanel("Tóm tắt GAM",
                 verbatimTextOutput("gam_summary"),
                 plotOutput("shap_plot")),
        tabPanel("Mức độ ảnh hưởng của từng biến",
                 plotOutput("importance_plot")),
        tabPanel("Ảnh hưởng của biến đã chọn theo mùa",
                 plotOutput("pdp_variable_season_plot"),
                 plotOutput("pdp_variable_season_facet"))
      )
    )
  )
)

# Định nghĩa logic máy chủ
server <- function(input, output) {
  # Biểu thức phản ứng để lọc dữ liệu dựa trên ngày đã chọn
  filtered_data <- reactive({
    cleaned_data %>%
      filter(day == day(input$date), month == month(input$date), year == year(input$date))
  })
  
  output$daily_summary <- renderPrint({
    newdata <- filtered_data()
    predictions <- predict(gam.model, newdata = newdata, type = "response")
    cat("Tổng dự đoán:", sum(predictions), "\n")
    cat("Tổng thực tế:", sum(newdata$rented_bike_count), "\n")
    
    predictions <- predict(gam.model, newdata = newdata, se.fit = TRUE)
    
    # Tính khoảng tin cậy
    alpha <- 0.05
    crit_value <- qnorm(1 - alpha / 2)
    lower_bound <- predictions$fit - crit_value * predictions$se.fit
    upper_bound <- predictions$fit + crit_value * predictions$se.fit
    cre <- cbind(sum(exp(lower_bound)), sum(exp(upper_bound)))
    
    # Tạo khung dữ liệu để vẽ
    results <- data.frame(
      rainfall_mm = newdata$rainfall_mm,
      fit = predictions$fit,
      lower = lower_bound,
      upper = upper_bound
    )
    cat("Khoảng tin cậy cho giá trị dự đoán:", cre ,"\n")
  })
  
  output$daily_plot <- renderPlot({
    newdata <- filtered_data()
    predictions <- predict(gam.model, newdata = newdata, type = "link", se.fit = TRUE)
    fit <- predictions$fit
    se <- predictions$se.fit
    lower_ci <- exp(fit - 1.96 * se)
    upper_ci <- exp(fit + 1.96 * se)
    
    plot(newdata$rented_bike_count, exp(fit), 
         xlab = "Số lượng quan sát", 
         ylab = "Số lượng dự đoán", 
         main = "Số lượng dự đoán với khoảng tin cậy")
    abline(a = 0, b = 1, col = "red")
    arrows(newdata$rented_bike_count, lower_ci, newdata$rented_bike_count, upper_ci, 
           angle = 90, code = 3, length = 0.1, col = "blue")
  })
  
  output$gam_summary <- renderPrint({
    selected_data <- cleaned_data %>%
      filter(day == day(input$date), 
             month == month(input$date), 
             year == year(input$date),
             hour == input$hour)
    
    if(nrow(selected_data) == 0) {
      cat("Không có dữ liệu cho ngày và giờ được chọn.")
      return(NULL)
    }
    
    actual_count <- selected_data$rented_bike_count
    
    gam_breakdown <- predict_parts(explainer = explainer_gam, new_observation = selected_data)
    breakdown_with_actual <- gam_breakdown %>%
      bind_rows(tibble(
        variable = "Giá trị thực tế",
        contribution = actual_count,
        variable_name = "Giá trị thực tế"
      ))
    
    cat("Ngày:", format(input$date, "%d-%m-%Y"), "\n")
    cat("Giờ:", input$hour, "\n\n")
    print(breakdown_with_actual)
  })
  
  output$shap_plot <- renderPlot({
    selected_data <- cleaned_data %>%
      filter(day == day(input$date), 
             month == month(input$date), 
             year == year(input$date),
             hour == input$hour)
    
    if(nrow(selected_data) == 0) {
      return(NULL)
    }
    
    shap_bike <- predict_parts(
      explainer = explainer_gam, 
      new_observation = selected_data, 
      type = "shap",
      B = 20
    )
    shap_bike %>%
      group_by(variable) %>%
      mutate(mean_val = mean(contribution)) %>%
      ungroup() %>%
      mutate(variable = fct_reorder(variable, abs(mean_val))) %>%
      ggplot(aes(contribution, variable, fill = mean_val > 0)) +
      geom_col(data = ~distinct(., variable, mean_val), 
               aes(mean_val, variable), 
               alpha = 0.5) +
      geom_boxplot(width = 0.5) +
      theme(legend.position = "none") +
      scale_fill_viridis_d() +
      labs(y = NULL,
           title = paste("Giá trị SHAP cho ngày", format(input$date, "%d-%m-%Y"), "trong khoảng thời gian từ", input$hour,"đến",input$hour + 1,"giờ"))
  })
  
  output$importance_plot <- renderPlot({
    gam <- model_parts(explainer_gam, loss_function = loss_root_mean_square)
    ggplot_imp <- function(...) {
      obj <- list(...)
      metric_name <- attr(obj[[1]], "loss_name")
      metric_lab <- paste(metric_name, 
                          "sau khi hoán vị\n(cao hơn chỉ mức độ quan trọng hơn)")
      
      full <- bind_rows(obj) %>%
        filter(variable != "_baseline_")
      
      perm_vals <- full %>% 
        filter(variable == "_full_model_") %>% 
        group_by(label) %>% 
        summarise(dropout_loss = mean(dropout_loss))
      
      p <- full %>%
        filter(variable != "_full_model_") %>%
        mutate(variable = fct_reorder(variable, dropout_loss)) %>%
        ggplot(aes(dropout_loss, variable)) 
      if(length(obj) > 1) {
        p <- p + 
          facet_wrap(vars(label)) +
          geom_vline(data = perm_vals, aes(xintercept = dropout_loss, color = label),
                     linewidth = 1.4, lty = 2, alpha = 0.7) +
          geom_boxplot(aes(color = label, fill = label), alpha = 0.2)
      } else {
        p <- p + 
          geom_vline(data = perm_vals, aes(xintercept = dropout_loss),
                     linewidth = 1.4, lty = 2, alpha = 0.7) +
          geom_boxplot(fill = "#91CBD765", alpha = 0.4)
        
      }
      p +
        theme(legend.position = "none") +
        labs(x = metric_lab, 
             y = NULL,  fill = NULL,  color = NULL)
    }
    ggplot_imp(gam)
  })
  
  custom_colors <- c("#0072B2", "#D55E00", "#009E73", "#CC79A7")
  
  ggplot_pdp <- function(obj, x) {
    
    p <- 
      as_tibble(obj$agr_profiles) %>%
      mutate(`_label_` = stringr::str_remove(`_label_`, "^[^_]*_")) %>%
      ggplot(aes(`_x_`, `_yhat_`)) +
      geom_line(data = as_tibble(obj$cp_profiles),
                aes(x = {{ x }}, group = `_ids_`),
                linewidth = 0.5, alpha = 0.05, color = "gray50")
    
    num_colors <- n_distinct(obj$agr_profiles$`_label_`)
    
    if (num_colors > 1) {
      p <- p + geom_line(aes(color = `_label_`), linewidth = 1.2, alpha = 0.8)
    } else {
      p <- p + geom_line(color = "midnightblue", linewidth = 1.2, alpha = 0.8)
    }
    
    p
  }
  
  output$pdp_variable_season_plot <- renderPlot({
    variable <- input$variable
    pdp_variable_season <- model_profile(explainer_gam, N = nrow(reg_data), 
                                         variables = variable, 
                                         groups = "seasons")
    
    ggplot_pdp(pdp_variable_season, !!sym(variable)) +
      scale_color_manual(values = custom_colors) +
      labs(x = variable, 
           y = "Số lượng xe thuê", 
           color = NULL)
  })
  
  output$pdp_variable_season_facet <- renderPlot({
    variable <- input$variable
    pdp_variable_season <- model_profile(explainer_gam, N = nrow(reg_data), 
                                         variables = variable, 
                                         groups = "seasons")
    
    as_tibble(pdp_variable_season$agr_profiles) %>%
      mutate(seasons = stringr::str_remove(`_label_`, "gam_")) %>%
      ggplot(aes(`_x_`, `_yhat_`, color = seasons)) +
      geom_line(linewidth = 1.2, alpha = 0.8, show.legend = FALSE) +
      facet_wrap(~seasons) +
      scale_color_manual(values = custom_colors) +
      labs(x = variable, 
           y = "Số lượng xe thuê", 
           color = NULL)
  })
}

# Chạy ứng dụng
shinyApp(ui = ui, server = server)
module LinkedData
  module Metrics
    def self.metrics_for_submission(submission,logger)
      logger.info("metrics_for_submission start")
      logger.flush
      begin
        submission.bring(:submissionStatus) if submission.bring?(:submissionStatus)

        cls_metrics = class_metrics(submission,logger)
        logger.info("class_metrics finished")
        logger.flush

        metrics = LinkedData::Models::Metric.new
        cls_metrics.each do |k,v|
          metrics.send("#{k}=",v)
        end
        metrics.individuals = number_individuals(submission)
        logger.info("individuals finished")
        logger.flush
        metrics.properties = number_properties(submission)
        logger.info("properties finished")
        logger.flush
        return metrics
      rescue Exception => e
        logger.error(e.message)
        logger.error(e)
        logger.flush
      end
      return nil
    end

    def self.class_metrics(submission,logger)
      t00 = Time.now
      size_page = 2500
      paging = LinkedData::Models::Class.in(submission)
                                        .include(:children,:definition)
                                        .page(1,size_page)
      cls_metrics = {}
      cls_metrics[:classes] = 0
      cls_metrics[:averageChildCount] = 0
      cls_metrics[:maxChildCount] = 0
      cls_metrics[:classesWithOneChild] = 0
      cls_metrics[:classesWithMoreThan25Children] = 0
      cls_metrics[:classesWithNoDefinition] = 0
      cls_metrics[:maxDepth] = 0
      page = 1
      children_counts = []
      begin
        t0 = Time.now
        page_classes = paging.page(page).all
        logger.info("Metrics Classes Page #{page} of #{page_classes.total_pages}"+
                    " classes retrieved in #{Time.now - t0} sec.")
        logger.flush
        classes_children = {}
        page_classes.each do |cls|
          cls_metrics[:classes] += 1
          #TODO: investigate
          #for some weird reason NIFSTD brings false:FalseClass here
          unless cls.definition.is_a?(Array) && cls.definition.length > 0
            cls_metrics[:classesWithNoDefinition] += 1
          end
          if cls.children.length > 24
            cls_metrics[:classesWithMoreThan25Children] += 1
          end
          if cls.children.length == 1
            cls_metrics[:classesWithOneChild] += 1
          end
          if cls.children.length > 0
            children_counts << cls.children.length
            classes_children[cls.id.to_s] = cls.children.map { |x| x.id.to_s}
          end
        end
        page = page_classes.next? ? page + 1 : nil
      end while(!page.nil?)
      roots_depth = [0]
      classes_children.each do |cls,children|
        next if children.nil?
        roots_depth << recursive_depth(cls,classes_children,1)
      end
      cls_metrics[:maxDepth]=roots_depth.max
      if children_counts.length > 0
        cls_metrics[:maxChildCount] = children_counts.max
        sum = 0
        children_counts.each do |x|
          sum += x
        end
        cls_metrics[:averageChildCount]  = (sum.to_f / children_counts.length).to_i
      end
      logger.info("Class metrics finished in #{Time.now - t00} sec.")
      return cls_metrics
    end

    def self.recursive_depth(cls,classes,depth)
      #Structural reasoning should fix cycles
      #but just in case a cap on recursivity
      #we known max depth is SNOMED with 36
      return 40 if depth > 40
      children = classes[cls]
      branch_depts = [depth+1]
      children.each do |ch|
        if classes[ch]
          branch_depts << recursive_depth(ch,classes,depth+1)
        end
      end
      return branch_depts.max
    end

    def self.number_individuals(submission)
      return count_owl_type(submission.id,"NamedIndividual")
    end

    def self.number_properties(submission)
      props = count_owl_type(submission.id,"DatatypeProperty")
      props += count_owl_type(submission.id,"ObjectProperty")
      return props
    end

    def self.count_owl_type(graph,name)
      owl_type = Goo.namespaces[:owl][name]
      query = <<eof
SELECT (COUNT(?s) as ?count) WHERE {
  GRAPH #{graph.to_ntriples} {
    ?s a #{owl_type.to_ntriples}
  } }
eof
      rs = Goo.sparql_query_client.query(query)
      rs.each do |sol|
        return sol[:count].object
      end
      return 0
    end

  end
end

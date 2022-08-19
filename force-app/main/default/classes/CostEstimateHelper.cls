public class CostEstimateHelper {
    /**
     * @description This method only trains data retrieval.
     * Uses Inliine Query in a for-loop, and checks if the cost estimate comes up in our map before
     * Creating a new entry in the map with an empty list
     * After that we always retrieve the the value behind the cost estimate Id, and add the opportunity there.
     * @author Dennis Grzyb
     * @param  estimates estimates description
     * @return           return description
     */
    public static Map<Id, List<Opportunity>> getOpportunities(List<CostEstimate__c> estimates) {
        Map<Id, List<Opportunity>> mapToReturn = new Map<Id, List<Opportunity>>();
        for (Opportunity opp : [SELECT Id, CostEstimate__c FROM Opportunity WHERE CostEstimate__c IN :estimates]) {
            if (!mapToReturn.containsKey(opp.CostEstimate__c)) {
                mapToReturn.put(opp.CostEstimate__c, new List<Opportunity>());
            }
            mapToReturn.get(opp.CostEstimate__c).add(opp);
        }
        return mapToReturn;
    }

    /**
     * @description Creates a Task based on Cost Estimates existing and having an Id
     * Leave dueDate null to create a task with automatic due date of tomorrow
     * @author Dennis Grzyb
     * @param  estimates estimates description
     * @param  dueDate   dueDate description
     * @return           return description
     */
    public static List<Task> createTask(List<CostEstimate__c> estimates, Date dueDate) {
        List<Task> newTasks = new List<Task>();
        for (CostEstimate__c estimate : estimates) {
            newTasks.add(
                new Task(
                    OwnerId = estimate.OwnerId,
                    Priority = 'Normal',
                    Status = 'Open',
                    Subject = 'Follow-Up Telefonat',
                    WhatId = estimate.Id,
                    ActivityDate = (dueDate != null ? dueDate : System.today().addDays(1))
                )
            );
        }
        return newTasks;
    }

    /**
     * @description Pulls all Cost Estimates + Their Opps from a subset of Opportunities, then sums
     * Up their Turnover (both general and won)
     * @author Dennis Grzyb
     * @param  opportunities opportunities description
     */
    public static void summarizeTurnover(List<Opportunity> opportunities) {
        Set<Id> costEstimateIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            costEstimateIds.add(opp.CostEstimate__c);
        }
        List<CostEstimate__c> estimates = [
            SELECT Id, Estimate__c, FalseEstimate__c, (SELECT Id, Amount, StageName FROM Opportunities__r)
            FROM CostEstimate__c
            WHERE Id IN :costEstimateIds
        ];
        for (CostEstimate__c est : estimates) {
            est.SumAllOpps__c = 0;
            est.SumWonOpps__c = 0;
            for (Opportunity opp : est.Opportunities__r) {
                est.SumAllOpps__c += opp.Amount;
                est.SumWonOpps__c += (opp.StageName == 'Closed Won' ? opp.Amount : 0);
            }
        }
        update estimates;
    }

    /**
     * @description Expects the Cost Estimate to be committed to database AFTER this method is done
     * Compares Estimate to the Sum of all Opps - Everytime, and adjusts the False Estimate Field accordingly
     * @author Dennis Grzyb
     * @param  costEstimates costEstimates description
     */
    public void compareEstimates(List<CostEstimate__c> costEstimates) {
        List<CostEstimate__c> costEstimatesToUpdate = new List<CostEstimate__c>();
        for (CostEstimate__c est : costEstimates) {
            if (
                !est.FalseEstimate__c &&
                ((est.Estimate__c / est.SumAllOpps__c) > 1.3 ||
                (est.Estimate__c / est.SumAllOpps__c) < 0.7)
            ) {
                est.FalseEstimate__c = true;
            } else if (
                est.FalseEstimate__c &&
                (est.Estimate__c / est.SumAllOpps__c) <= 1.3 &&
                (est.Estimate__c / est.SumAllOpps__c) >= 0.7
            ) {
                est.FalseEstimate__c = false;
            }
        }
    }

    /**
     * @description This method takes any kind of SOBject and first gets the type of the SObject list given
     * After that, we check if there is a default task setting for this SObject Type
     * If yes, we subdivide our TaskSubjects__c and create tasks for our SObjects.
     * This is hardly possible with anything other than a nested for loop
     * @author Dennis Grzyb
     * @param  newSobjects newSobjects description
     */
    public static void createStartingTasks(List<SObject> newSobjects) {
        SObjectType sobjType = newSobjects.getSObjectType();

        DefaultTaskSettings__mdt setting;
        try {
            setting = [
                SELECT TaskSubjects__c
                FROM DefaultTaskSettings__mdt
                WHERE SObjectName__c = :sobjType.getDescribe().getName()
                LIMIT 1
            ];
        } catch (Exception e) {
            //If we don't find anything, that's okay too.
        }

        if (setting != null) {
            List<Task> newTasksToInsert = new List<Task>();
            List<String> subjects = setting.TaskSubjects__c.split(';');
            for (SObject sobj : newSObjects) {
                for (String subject : subjects) {
                    Task startingTask = new Task(
                        Subject = subject,
                        Status = 'Open',
                        WhatId = String.valueOf(sobj.get('Id')),
                        ActivityDate = Date.today().addDays(3)
                    );
                    //This here is completely optional! I only added it for completeness' sake.
                    if (doesFieldExist(sobjType.getDescribe().getName(), 'OwnerId')) {
                        startingTask.OwnerId = String.valueOf(sobj.get('OwnerId'));
                    }
                    newTasksToInsert.add(startingTask);
                }
            }
            if (!newTasksToInsert.isEmpty()) {
                insert newTasksToInsert;
            }
        }
    }

    /**
     * @description This function is a helper to assign the OwnerId of a record as the Task Assignee, if the record even has a RecordId.
     * Otherwise it will be the CreatedById.
     * @author Dennis Grzyb
     * @param  objName   objName description
     * @param  fieldName fieldName description
     * @return           return description
     */
    public static Boolean doesFieldExist(String objName, string fieldName) {
        try {
            SObject so = Schema.getGlobalDescribe().get(objName).newSObject();
            return so.getSobjectType().getDescribe().fields.getMap().containsKey(fieldName);
        } catch (Exception ex) {
        }

        return false;
    }
}

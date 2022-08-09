public class CostEstimateHelper {
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

    public void compareEstimates(List<Opportunity> opportunities) {
        Set<Id> costEstimateIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            costEstimateIds.add(opp.CostEstimate__c);
        }
        List<CostEstimate__c> estimates = [
            SELECT Id, SumAllOpps__c, FalseEstimate__c, (SELECT Id, Amount, StageName FROM Opportunities__r)
            FROM CostEstimate__c
            WHERE Id IN :costEstimateIds AND FalseEstimate__c = FALSE
        ];
        List<CostEstimate__c> costEstimatesToUpdate = new List<CostEstimate__c>();
        for (CostEstimate__c est : estimates) {
            if (((est.Estimate__c / est.SumAllOpps__c) > 1.3 || (est.Estimate__c / est.SumAllOpps__c) < 0.7)) {
                est.FalseEstimate__c = true;
                costEstimatesToUpdate.add(est);
            }
        }
        if (!costEstimatesToUpdate.isEmpty()) {
            update costEstimatesToUpdate;
        }
    }

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

    public static Boolean doesFieldExist(String objName, string fieldName) {
        try {
            SObject so = Schema.getGlobalDescribe().get(objName).newSObject();
            return so.getSobjectType().getDescribe().fields.getMap().containsKey(fieldName);
        } catch (Exception ex) {
        }

        return false;
    }
}
